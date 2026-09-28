#!/usr/bin/env python3
"""Contrôles automatiques après le test à l'écran : requêtes envoyées à Ollama et fichiers de l'app."""
import glob
import json
import os
import subprocess
import sys
import urllib.request

SMOKE = sys.argv[1]
HOME = os.path.expanduser("~")
DATA = os.path.join(HOME, "Library/Application Support/OllamaChat")
VERIFY_PREFIX = "Relis attentivement ta réponse précédente"


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return default


def load_jsonl(path):
    items = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    items.append(json.loads(line))
                except Exception:  # noqa: BLE001
                    pass
    except FileNotFoundError:
        pass
    return items


requests = sorted(load_jsonl("/tmp/requests.jsonl"), key=lambda r: r["seq"])
phases = []
for line in open("/tmp/phases.txt", encoding="utf-8"):
    parts = line.split()
    if len(parts) == 2:
        phases.append((parts[0], int(parts[1])))
conversations = load_json(os.path.join(DATA, "conversations.json"), [])


def in_phase(name):
    starts = [seq for phase, seq in phases if phase == name]
    if not starts:
        return []
    start = starts[0]
    later = [seq for _, seq in phases if seq > start]
    end = min(later) if later else float("inf")
    return [r for r in requests if start < r["seq"] <= end]


def body(r):
    return r.get("body") or {}


def messages(r):
    return body(r).get("messages") or []


def system(r):
    items = messages(r)
    return items[0].get("content", "") if items and items[0].get("role") == "system" else ""


def last_user(r):
    for message in reversed(messages(r)):
        if message.get("role") == "user":
            return message.get("content", "")
    return ""


def kind(r):
    if r["path"].startswith("/api/embed"):
        return "embed"
    b = body(r)
    if b.get("stream") is False:
        if b.get("format"):
            return "memory"
        first = messages(r)[0].get("content", "") if messages(r) else ""
        return "title" if first.startswith("Donne un titre") else "complete"
    return "chat"


def chats(name):
    return [r for r in in_phase(name) if kind(r) == "chat"]


def options(r):
    return body(r).get("options") or {}


def conversation_with(text):
    for conversation in conversations:
        if any(text in (m.get("content") or "") for m in conversation.get("messages", [])):
            return conversation
    return None


def context_length(model):
    try:
        request = urllib.request.Request("http://localhost:11434/api/show", data=json.dumps({"model": model}).encode())
        info = json.load(urllib.request.urlopen(request, timeout=10)).get("model_info", {})
        return next((v for k, v in info.items() if k.endswith(".context_length")), None)
    except Exception:  # noqa: BLE001
        return None


results = []


def check(name, ok, detail="", informative=False):
    status = "OK" if ok else ("INFO" if informative else "ÉCHEC")
    results.append(f"[{status}] {name}" + (f" — {detail}" if detail else ""))


def first(items):
    return items[0] if items else {}


# Réglages › Personnalisation
about = subprocess.run(["defaults", "read", "com.ollamachat.desktop", "aboutMe"], capture_output=True, text=True).stdout.strip()
check("Réglages : « À propos de moi » saisi à l'écran", "Camille" in about, repr(about[:80]))

# Mode raisonnement
r = first(chats("reflexion"))
check("Réflexion : think=true envoyé", body(r).get("think") is True, f"think={body(r).get('think')!r}")
check("Réflexion : le modèle a réfléchi", r.get("response", {}).get("thinking_chars", 0) > 0, f"{r.get('response', {}).get('thinking_chars', 0)} caractères")
check("Réflexion : réponse obtenue", bool(r.get("response", {}).get("content")), repr(r.get("response", {}).get("content", "")[:120]))
check("Contexte : num_ctx = 8192 par défaut", options(r).get("num_ctx") == 8192, f"options={options(r)}")
check("Personnalisation : « À propos de moi » dans le prompt système", "Camille" in system(r))
check("Prompt système : date du jour", system(r).startswith("Date du jour :"), repr(system(r)[:60]))
conversation = conversation_with("Combien font 17 fois 23") or {}
assistant = next((m for m in conversation.get("messages", []) if m.get("role") == "assistant"), {})
check("Réflexion : durée mesurée", assistant.get("thinkingSeconds") is not None, f"{assistant.get('thinkingSeconds')}")
titles = [x for x in in_phase("reflexion") if kind(x) == "title"]
check("Titre automatique : requête envoyée au modèle", bool(titles))
check("Titre automatique : même contexte que la conversation (pas de rechargement)",
      bool(titles) and options(titles[0]).get("num_ctx") == options(r).get("num_ctx"), f"{[options(t) for t in titles]}")
check("Titre automatique : titre remplacé", conversation.get("titleGenerated") is True
      and conversation.get("title") != "Combien font 17 fois 23 ? Réponds en une phrase.", repr(conversation.get("title")))

# Réflexion désactivée et profil Rigoureux
r = first(chats("options"))
check("⌥⌘R : réflexion désactivée (think=false)", body(r).get("think") is False, f"think={body(r).get('think')!r}")
check("⌥⌘2 : profil Rigoureux, température 0,3", options(r).get("temperature") == 0.3, f"options={options(r)}")
check("Profil Rigoureux : consignes dans le prompt système", "Distingue clairement" in system(r))

# Vérifier
r = first(chats("verification"))
check("Vérifier : demande de vérification envoyée", last_user(r).startswith(VERIFY_PREFIX), repr(last_user(r)[:60]))

# Modifier un message
r = first(chats("edition"))
check("Modifier : texte modifié envoyé", last_user(r) == "Quelle est la capitale du Canada ?", repr(last_user(r)))
edited = conversation_with("capitale du Canada") or {}
contents = " ".join(m.get("content", "") for m in edited.get("messages", []))
check("Modifier : la suite de la conversation est remplacée",
      "Australie" not in contents and not any(m.get("kind") == "verification" for m in edited.get("messages", [])),
      f"{len(edited.get('messages', []))} messages")

# Mémoire
remembered = json.dumps(load_json(os.path.join(SMOKE, "memoires-apres-retiens.json"), []), ensure_ascii=False)
check("Mémoire : « Retiens que… » enregistré", "infirmière de nuit" in remembered, remembered[:200])
command = conversation_with("Retiens que je travaille") or {}
flag = next((m.get("memoryUpdated") for m in command.get("messages", []) if m.get("content", "").startswith("Retiens")), None)
check("Mémoire : message marqué « Mémoire mise à jour »", flag is True)
r = first(chats("memoire-rappel"))
check("Mémoire : souvenir donné au modèle dans une autre conversation", "infirmière de nuit" in system(r), repr(system(r)[-160:]))
check("Mémoire : souvenir à la première personne présenté comme parole de l'utilisateur", "L’utilisateur a dit" in system(r))
check("Mémoire : le modèle s'en sert", "infirm" in r.get("response", {}).get("content", "").lower(),
      repr(r.get("response", {}).get("content", "")[:160]), informative=True)
extractions = [x for x in requests if kind(x) == "memory"]
check("Mémoire automatique : extraction lancée en quittant une conversation", bool(extractions), f"{len(extractions)} requête(s)")
for x in extractions[:3]:
    results.append(f"       extraction → {x.get('response', {}).get('content', '')[:200]!r}")
forgotten = json.dumps(load_json(os.path.join(SMOKE, "memoires-apres-oublie.json"), []), ensure_ascii=False)
check("Mémoire : « Oublie… » retire le souvenir", "de nuit" not in forgotten, forgotten[:200])

# Recherche web par outils
web = chats("web-outils")
r = first(web)
tools = [t.get("function", {}).get("name") for t in body(r).get("tools") or []]
check("Web (outils) : web_search et web_fetch proposés", tools == ["web_search", "web_fetch"], f"{tools}")
check("Web : contexte porté à 16 384", options(r).get("num_ctx") == 16384, f"options={options(r)}")
check("Web : consigne de citer les sources", "web_search" in system(r))
tool_messages = [m for x in web for m in messages(x) if m.get("role") == "tool"]
called = [c.get("function", {}).get("name") for x in web for c in x.get("response", {}).get("tool_calls", [])]
check("Web (outils) : le modèle a appelé un outil", bool(called), f"{called}", informative=True)
if called:
    check("Web (outils) : résultats renvoyés au modèle", any("TOURNESOL-42" in m.get("content", "") or "Lyon" in m.get("content", "") for m in tool_messages),
          f"{len(tool_messages)} message(s) d'outil")
    searched = conversation_with("Cherche sur le web") or {}
    answer = next((m for m in reversed(searched.get("messages", [])) if m.get("role") == "assistant"), {})
    check("Web (outils) : étapes et sources affichées", bool(answer.get("steps")) and bool(answer.get("sources")),
          f"étapes={[s.get('kind') for s in answer.get('steps', [])]} sources={[s.get('tag') for s in answer.get('sources', [])]}")

# Vision
r = first(chats("vision"))
last = next((m for m in reversed(messages(r)) if m.get("role") == "user"), {})
limit = context_length("moondream")
check("Vision : image envoyée au modèle", bool(last.get("images")), f"model={body(r).get('model')} images={last.get('images')}")
check("Vision : réponse obtenue", bool(r.get("response", {}).get("content")), repr(r.get("response", {}).get("content", "")[:160]))
check("Vision : pas de paramètre think pour un modèle qui ne raisonne pas", "think" not in body(r))
check("Contexte : limité au maximum du modèle", limit is None or options(r).get("num_ctx", 0) <= limit, f"num_ctx={options(r).get('num_ctx')} max={limit}")

# Recherche préalable
r = first(chats("recherche-prealable"))
check("Web (préalable) : pas d'outils pour un modèle qui n'en gère pas", "tools" not in body(r) or not body(r).get("tools"))
check("Web (préalable) : résultats joints à la question", "Résultats de la recherche" in last_user(r) and "TOURNESOL-42" in last_user(r)
      and "Question de l’utilisateur" in last_user(r), repr(last_user(r)[:100]))
presearch = conversation_with("Quelle est la météo à Lyon aujourd'hui ?") or {}
answer = next((m for m in reversed(presearch.get("messages", [])) if m.get("role") == "assistant"), {})
check("Web (préalable) : étape et sources affichées", bool(answer.get("steps")) and bool(answer.get("sources")),
      f"étapes={[s.get('detail') for s in answer.get('steps', [])]} sources={len(answer.get('sources', []))}")

# Documents
docs = in_phase("documents")
embeds = [x for x in docs if kind(x) == "embed"]
check("Documents : indexation par le modèle d'embeddings", any(body(x).get("model", "").startswith("all-minilm") for x in embeds),
      f"{len(embeds)} requête(s), {sum(body(x).get('input_count', 0) for x in embeds)} passages")
r = first([x for x in docs if kind(x) == "chat"])
check("Documents : extraits joints à la question", "Extraits des documents joints" in last_user(r), repr(last_user(r)[:80]))
check("Documents : le bon passage retrouvé dans le rapport long", "12 000 euros" in last_user(r))
check("Documents : consigne de citer [D1]…", "rapport-long.txt" in system(r) and "[D1]" in system(r))
check("Documents : contexte porté à 16 384", options(r).get("num_ctx") == 16384, f"options={options(r)}")
check("Documents : le modèle répond avec le budget", "12" in r.get("response", {}).get("content", ""),
      repr(r.get("response", {}).get("content", "")[:160]), informative=True)
with_docs = conversation_with("budget total du projet Hibiscus") or {}
documents = with_docs.get("documents", [])
check("Documents : trois documents prêts", len([d for d in documents if d.get("status") == "ready"]) >= 3,
      f"{[(d.get('name'), d.get('status'), d.get('chunkCount'), d.get('pageCount'), d.get('embeddingModel'), d.get('error')) for d in documents]}")
answer = next((m for m in with_docs.get("messages", []) if m.get("role") == "assistant"), {})
check("Documents : sources [D…] affichées", any(s.get("tag", "").startswith("D") for s in answer.get("sources", [])),
      f"{[(s.get('tag'), s.get('title'), s.get('detail')) for s in answer.get('sources', [])]}")
r = first(chats("docx"))
check("Word (⌘O) : texte du .docx retrouvé", "Lavande-2026" in last_user(r), repr(last_user(r)[:80]))
check("Word (⌘O) : réponse", "lavande" in r.get("response", {}).get("content", "").lower(),
      repr(r.get("response", {}).get("content", "")[:160]), informative=True)

# Export
exported = ""
try:
    exported = open(os.path.join(SMOKE, "export.md"), encoding="utf-8").read()
except FileNotFoundError:
    pass
check("Export Markdown : fichier écrit", "## Vous" in exported and "Hibiscus" in exported, f"{len(exported)} caractères")

# Saisie rapide
r = first(chats("saisie-rapide"))
check("Saisie rapide (⌥Espace) : question envoyée", last_user(r) == "Dis bonjour en une phrase.", repr(last_user(r)))
quick = conversation_with("Dis bonjour en une phrase.") or {}
check("Saisie rapide : réponse dans une nouvelle conversation", any(m.get("role") == "assistant" and m.get("content") for m in quick.get("messages", [])))

# Cohérence générale
last_ctx = {}
mismatches = []
for x in requests:
    if kind(x) == "chat":
        last_ctx[body(x).get("model")] = options(x).get("num_ctx")
    elif kind(x) in ("title", "memory"):
        model = body(x).get("model")
        if model in last_ctx and options(x).get("num_ctx") != last_ctx[model]:
            mismatches.append((x["seq"], kind(x), model, options(x).get("num_ctx"), last_ctx[model]))
check("Titres et mémoire : même num_ctx que la dernière réponse du modèle", not mismatches, f"{mismatches}")
errors = [(x["seq"], x.get("status"), x.get("relay_error"), x.get("response", {}).get("error")) for x in requests
          if x.get("status", 200) >= 400 or x.get("relay_error") or x.get("response", {}).get("error")]
check("Aucune erreur renvoyée par Ollama", not errors, f"{errors}")
failed = [m.get("errorText") for c in conversations for m in c.get("messages", []) if m.get("errorText")]
check("Aucune erreur affichée dans les conversations", not failed, f"{failed}")
crashes = glob.glob(os.path.join(HOME, "Library/Logs/DiagnosticReports/*OllamaChat*"))
check("Aucun plantage", not crashes, f"{crashes}")
check("App ouverte à la fin", subprocess.run(["pgrep", "-x", "OllamaChat"], capture_output=True).returncode == 0)

summary = f"{sum(r.startswith('[OK]') for r in results)} OK, {sum(r.startswith('[ÉCHEC]') for r in results)} échec(s), {sum(r.startswith('[INFO]') for r in results)} info"
with open(os.path.join(SMOKE, "verification.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(results) + "\n\n" + summary + "\n")
print("\n".join(results))
print(summary)

# Diagnostics détaillés
lines = ["# Requêtes envoyées à Ollama", ""]
for x in requests:
    b = body(x)
    response = x.get("response", {})
    lines.append(f"#{x['seq']} {kind(x)} {x['path']} model={b.get('model')} think={b.get('think')!r} options={b.get('options')} "
                 f"tools={[t.get('function', {}).get('name') for t in b.get('tools') or []]} format={'oui' if b.get('format') else 'non'} "
                 f"messages={[m.get('role') for m in messages(x)]} {x.get('seconds')} s status={x.get('status')}")
    if kind(x) == "embed":
        lines.append(f"    entrées={b.get('input_count')} → {response.get('embeddings')} vecteurs")
        continue
    if system(x):
        lines.append(f"    système : {system(x)[:600]!r}")
    for m in messages(x)[1:] if system(x) else messages(x):
        lines.append(f"    {m.get('role')} : {str(m.get('content', ''))[:400]!r}" + (f" images={m.get('images')}" if m.get("images") else "")
                     + (f" tool_calls={m.get('tool_calls')}" if m.get("tool_calls") else ""))
    lines.append(f"    → réponse : {response.get('content', '')[:500]!r} (réflexion : {response.get('thinking_chars')} car.) outils={response.get('tool_calls')} {response.get('error', '')}")
lines += ["", "# Conversations", ""]
for c in conversations:
    lines.append(f"## {c.get('title')} | modèle={c.get('model')} profil={c.get('profileID')} réflexion={c.get('thinking')} web={c.get('webSearch')} "
                 f"titre auto={c.get('titleGenerated')} documents={[(d.get('name'), d.get('status'), d.get('chunkCount'), d.get('embeddingModel')) for d in c.get('documents', [])]}")
    for m in c.get("messages", []):
        lines.append(f"  - {m.get('role')} {m.get('kind')} : {m.get('content', '')[:300]!r} | réflexion={len(m.get('thinking', ''))} car. "
                     f"{m.get('thinkingSeconds')} s | images={m.get('images')} | étapes={[(s.get('kind'), s.get('detail'), s.get('resultCount'), s.get('error')) for s in m.get('steps', [])]} "
                     f"| sources={[(s.get('tag'), s.get('title')) for s in m.get('sources', [])]} | erreur={m.get('errorText')} | mémoire={m.get('memoryUpdated')}")
lines += ["", "# Mémoire", json.dumps(load_json(os.path.join(DATA, "memories.json"), []), ensure_ascii=False, indent=1)]
lines += ["", "# Recherches reçues par le faux SearXNG"] + [json.dumps(x, ensure_ascii=False) for x in load_jsonl("/tmp/searx.log")]
lines += ["", "# Export", exported[:3000]]
try:
    ollama_log = open("/tmp/ollama.log", encoding="utf-8", errors="replace").read().splitlines()
    lines += ["", "# Journal d'Ollama (erreurs et fin)"] + [l for l in ollama_log if "error" in l.lower() or "level=WARN" in l][:60] + ollama_log[-40:]
except FileNotFoundError:
    pass
with open(os.path.join(SMOKE, "diagnostics.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
