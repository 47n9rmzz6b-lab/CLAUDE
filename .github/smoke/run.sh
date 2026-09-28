#!/bin/bash
# Vérification complète d'Ollama Chat sur un Mac de la CI (temporaire).
set -u
ROOT="$GITHUB_WORKSPACE"
TOOLS="$ROOT/.github/smoke"
APP="$ROOT/OllamaChat/build/Ollama Chat.app"
SMOKE="$ROOT/OllamaChat/.smoke"
DATA="$HOME/Library/Application Support/OllamaChat"
DOCS=/tmp/docs
mkdir -p "$SMOKE" "$DOCS"
: > /tmp/phases.txt

shot() {
  screencapture -x "/tmp/$1.png" && sips -Z 1400 -s format jpeg -s formatOptions 72 "/tmp/$1.png" --out "$SMOKE/$1.jpg" >/dev/null && echo "  [capture] $1"
}
key() { osascript -e "tell application \"System Events\" to $1" >/dev/null; sleep 0.5; }
paste() { printf '%s' "$1" | LANG=en_US.UTF-8 pbcopy; key 'keystroke "v" using command down'; }
enter() { key 'key code 36'; }
esc() { key 'key code 53'; }
activate() { osascript -e 'tell application "Ollama Chat" to activate' >/dev/null; sleep 1; }
ax() { /tmp/ax "$@"; }
state() { python3 -c "import json,sys;print(json.load(open('/tmp/proxy_state.json'))[sys.argv[1]])" "$1" 2>/dev/null || echo 0; }
phase() { echo; echo "=== $* ==="; echo "$1 $(state seq)" >> /tmp/phases.txt; allow_prompts; }
LAST_CHAT=0
arm() { LAST_CHAT=$(state chat); }
# Attend une nouvelle requête /api/chat, puis 6 s sans aucune requête en cours (réponse, titre, mémoire).
waitidle() {
  local timeout=${1:-240} start quiet=0
  start=$(date +%s)
  while [ "$(state chat)" -le "$LAST_CHAT" ]; do
    if [ $(( $(date +%s) - start )) -ge 40 ]; then echo "  (aucune nouvelle requête /api/chat)"; break; fi
    sleep 1
  done
  while [ $quiet -lt 6 ]; do
    if [ "$(state inflight)" = "0" ]; then quiet=$((quiet + 1)); else quiet=0; fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then echo "  (délai dépassé : $(state inflight) requête(s) en cours)"; break; fi
    sleep 1
  done
  echo "  terminé en $(( $(date +%s) - start )) s"
}
# Alertes système (réseau local, reconnaissance vocale, micro) : validées pour ne pas masquer l'app.
allow_prompts() { /tmp/ax allow; }
close_settings() { AX_WINDOW=com_apple_SwiftUI_Settings_window /tmp/ax close >/dev/null; sleep 0.5; }
# Fenêtre principale au premier plan, sans réglages, feuille, menu ni bulle ouverts.
reset_ui() { allow_prompts; close_settings; activate; esc; }
# Clic dans la zone de saisie (la dernière zone de texte de la fenêtre principale) avant de taper.
focus_composer() { AX_WINDOW=main /tmp/ax click "" AXTextArea -1 >/dev/null || echo "  zone de saisie introuvable"; sleep 0.3; }
send() { focus_composer; paste "$1"; arm; enter; waitidle "${2:-240}"; }
# Envoi dans le champ qui a déjà le focus (saisie rapide).
send_here() { paste "$1"; arm; enter; waitidle "${2:-240}"; }
# État des boutons de la zone de saisie, lu dans leur bulle d'aide.
web_on() { ax find "Recherche web activée" >/dev/null; }
thinking_on() { ax find "Le modèle réfléchit avant de répondre" >/dev/null; }
set_web() { if [ "$1" = on ]; then web_on || key 'keystroke "i" using {command down, option down}'; else web_on && key 'keystroke "i" using {command down, option down}'; fi; web_on && echo "  web : activé" || echo "  web : désactivé"; }
choose_model() {
  ax click "Modèle utilisé pour cette conversation" >/dev/null; sleep 1.5
  ax press "$1" AXMenuItem || { ax dump > "$SMOKE/ax-menu-modeles.txt"; esc; }
  sleep 1
  echo "  modèle : $(ax find "Modèle utilisé pour cette conversation" | head -1)"
}

echo "== Préparation"
swiftc -O "$TOOLS/ax.swift" -o /tmp/ax || exit 1
python3 "$TOOLS/make_docs.py" "$DOCS"
(python3 "$TOOLS/proxy.py" > /tmp/proxy.out 2>&1 &)
(python3 "$TOOLS/searx.py" > /tmp/searx.out 2>&1 &)
until [ -f /tmp/pull.done ]; do sleep 5; done
ollama list
for model in qwen3:0.6b moondream all-minilm; do
  echo "$model : $(curl -s http://localhost:11434/api/show -d "{\"model\":\"$model\"}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("capabilities"), [v for k,v in d.get("model_info",{}).items() if k.endswith(".context_length")])')"
done
defaults write com.ollamachat.desktop serverURL -string "http://localhost:11435"
defaults write com.ollamachat.desktop webSearchProvider -string searxng
defaults write com.ollamachat.desktop searxngURL -string "http://localhost:8765"
defaults write com.ollamachat.desktop defaultModel -string "qwen3:0.6b"
sleep 2

phase lancement "Lancement"
open "$APP"
sleep 8
allow_prompts
pgrep -x OllamaChat >/dev/null && echo "  app lancée" || echo "  L'APP NE TOURNE PAS"
ax dump > "$SMOKE/ax-accueil.txt"
head -3 "$SMOKE/ax-accueil.txt"
shot 01-accueil

phase reglages "Réglages › Personnalisation (saisie à l'écran)"
activate
key 'keystroke "," using command down'
sleep 2
allow_prompts
ax click "=Personnalisation" AXButton
sleep 1.5
AX_WINDOW=com_apple_SwiftUI_Settings_window ax dump > "$SMOKE/ax-personnalisation.txt"
# On ne colle que si la zone a été trouvée : sinon le texte irait ailleurs (l'adresse du serveur…).
if AX_WINDOW=Personnalisation ax click "" AXTextArea 0; then
  sleep 0.5
  paste "Je m'appelle Camille. Je suis infirmière à Lyon et j'ai un Mac mini M4."
  sleep 1
else
  defaults write com.ollamachat.desktop aboutMe -string "Je m'appelle Camille (réglage écrit par le test)."
fi
shot 02-reglages-personnalisation
close_settings
echo "  aboutMe = $(defaults read com.ollamachat.desktop aboutMe 2>/dev/null)"

phase reflexion "Mode raisonnement, durée de réflexion, titre automatique"
reset_ui
key 'keystroke "n" using command down'
thinking_on && echo "  réflexion : activée" || echo "  réflexion : désactivée"
send "Combien font 17 fois 23 ? Réponds en une phrase." 300
shot 03-reflexion
ax click "A réfléchi" || ax click "Réflexion"
sleep 1
shot 04-reflexion-ouverte
ax click "Mémoire de travail du modèle"
sleep 1.5
shot 05-jauge-contexte
esc

phase options "Réflexion désactivée (⌥⌘R), profil Rigoureux (⌥⌘2)"
key 'keystroke "r" using {command down, option down}'
key 'keystroke "2" using {command down, option down}'
sleep 1
thinking_on && echo "  réflexion : activée" || echo "  réflexion : désactivée"
ax find "Profil de réponse" | head -1
shot 06-options
send "Quelle est la capitale de l'Australie ?"

phase verification "Bouton Vérifier (⇧⌘V)"
arm
key 'keystroke "v" using {command down, shift down}'
waitidle 240
shot 07-verification

phase edition "Modifier le dernier message (↑ dans la zone vide)"
focus_composer
key 'key code 126'
sleep 1.5
shot 08-edition
key 'keystroke "a" using command down'
paste "Quelle est la capitale du Canada ?"
arm
key 'key code 36 using command down'
waitidle 240
shot 09-apres-edition

phase memoire "Mémoire : « Retiens que… »"
reset_ui
key 'keystroke "n" using command down'
send "Retiens que je travaille comme infirmière de nuit à Lyon."
shot 10-memoire-commande
cp "$DATA/memories.json" "$SMOKE/memoires-apres-retiens.json" 2>/dev/null

phase memoire-rappel "Mémoire utilisée dans une nouvelle conversation"
key 'keystroke "n" using command down'
send "Quel est mon métier ? Réponds en une phrase." 300
shot 11-memoire-rappel

phase oubli "Mémoire : « Oublie… »"
send "Oublie que je travaille de nuit."
cp "$DATA/memories.json" "$SMOKE/memoires-apres-oublie.json" 2>/dev/null

phase web-outils "Recherche web par outils (qwen3)"
reset_ui
key 'keystroke "n" using command down'
set_web on
send "Quelle est la météo à Lyon aujourd'hui ? Cherche sur le web et cite ta source." 360
shot 12-recherche-web

phase vision "Image avec un modèle de vision (moondream)"
reset_ui
key 'keystroke "n" using command down'
set_web off
choose_model moondream
open -a "$APP" "$DOCS/formes.png"
sleep 3
shot 13-image-jointe
send "Décris cette image en une phrase." 360
shot 14-vision

phase recherche-prealable "Recherche préalable pour un modèle sans outils (moondream)"
set_web on
send "Quelle est la météo à Lyon aujourd'hui ?" 360
shot 15-recherche-prealable

phase documents "Documents (texte, PDF, rapport long indexé)"
reset_ui
key 'keystroke "n" using command down'
set_web off
choose_model qwen3
open -a "$APP" "$DOCS/notes-projet.txt" "$DOCS/lettre.pdf" "$DOCS/rapport-long.txt"
sleep 12
shot 16-documents
send "Quel est le budget total du projet Hibiscus ? Cite ta source." 360
shot 17-documents-reponse

phase docx "Document Word joint avec ⌘O"
key 'keystroke "o" using command down'
sleep 2
shot 18-panneau-joindre
key 'keystroke "g" using {command down, shift down}'
sleep 1
paste "$DOCS/memo.docx"
enter
sleep 2
enter
sleep 6
shot 19-docx-joint
send "Quel est le mot de passe du wifi de l'atelier ?" 360
shot 20-docx-reponse

phase export "Export Markdown (⇧⌘E)"
reset_ui
touch /tmp/export.marker
sleep 1
key 'keystroke "e" using {command down, shift down}'
sleep 2
shot 21-export
enter
sleep 3
exported=$(find "$HOME" -name "*.md" -newer /tmp/export.marker -not -path "*/Library/*" 2>/dev/null | head -1)
echo "  fichier exporté : ${exported:-aucun}"
[ -n "$exported" ] && cp "$exported" "$SMOKE/export.md"

phase saisie-rapide "Saisie rapide (⌥Espace) depuis une autre application"
osascript -e 'tell application "Finder" to activate'
sleep 1.5
key 'key code 49 using option down'
sleep 1.5
shot 22-saisie-rapide
send_here "Dis bonjour en une phrase." 240
shot 23-apres-saisie-rapide

phase modeles "Gestion des modèles (⇧⌘M)"
reset_ui
key 'keystroke "m" using {command down, shift down}'
sleep 2
shot 24-modeles
esc

phase reglages-onglets "Onglets des réglages"
reset_ui
key 'keystroke "," using command down'
sleep 2
number=25
for entry in "Général:general" "Génération:generation" "Personnalisation:personnalisation" "Mémoire:memoire" \
             "Recherche web:recherche-web" "Documents:documents" "Dictée:dictee"; do
  tab=${entry%%:*}
  ax click "=$tab" >/dev/null || echo "  onglet introuvable : $tab"
  sleep 1.5
  if [ "$tab" = "Recherche web" ]; then
    AX_WINDOW="Recherche web" ax click "Tester une recherche"
    sleep 3
  fi
  shot "$number-reglages-${entry##*:}"
  number=$((number + 1))
done
ax dump > "$SMOKE/ax-reglages.txt"
close_settings

phase dictee "Dictée"
reset_ui
ax click "Dicter un message"
sleep 4
shot 32-dictee
allow_prompts
sleep 3
allow_prompts
sleep 3
shot 33-dictee-apres
AX_WINDOW=main ax find "" AXStaticText | grep -i "micro\|dict\|reconnaissance" || true
ax click "Arrêter la dictée" >/dev/null 2>&1
pgrep -x OllamaChat >/dev/null && echo "  app toujours ouverte" || echo "  L'APP S'EST FERMÉE"

phase sombre "Mode sombre"
reset_ui
title=$(python3 -c "
import json, os
for c in json.load(open(os.path.expanduser('~/Library/Application Support/OllamaChat/conversations.json'))):
    if any('Hibiscus' in m.get('content', '') for m in c['messages']):
        print(c['title']); break
")
echo "  conversation des documents : $title"
[ -n "$title" ] && ax click "=$title"
sleep 1
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
sleep 3
shot 34-sombre
ax dump > "$SMOKE/ax-documents.txt"

phase relance "Relance de l'app"
count_before=$(python3 -c "import json,os; print(len(json.load(open(os.path.expanduser('~/Library/Application Support/OllamaChat/conversations.json')))))")
key 'keystroke "q" using command down'
sleep 4
pgrep -x OllamaChat >/dev/null && echo "  toujours ouverte après ⌘Q" || echo "  fermée"
open "$APP"
sleep 8
shot 35-relance
pgrep -x OllamaChat >/dev/null && echo "  relancée" || echo "  L'APP NE TOURNE PAS"
echo "  conversations avant : $count_before, après : $(python3 -c "import json,os; print(len(json.load(open(os.path.expanduser('~/Library/Application Support/OllamaChat/conversations.json')))))")"
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'

echo "  adresse du serveur : $(defaults read com.ollamachat.desktop serverURL 2>/dev/null)"
echo; echo "== Rapport"
python3 "$TOOLS/report.py" "$SMOKE"
