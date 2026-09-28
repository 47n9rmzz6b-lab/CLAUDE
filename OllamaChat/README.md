# Ollama Chat

Ollama Chat est une application Mac native pour discuter avec vos modèles [Ollama](https://ollama.com) dans une fenêtre semblable à celle de l’application Claude, sans passer par le Terminal.

## Fonctions

**Discuter**

- **Conversations** : elles sont enregistrées et classées par date (Aujourd’hui, Hier, 7 derniers jours…) dans une barre latérale, avec recherche, renommage et suppression. Au lancement, l’application rouvre la dernière conversation affichée. Le modèle leur donne un titre court après la première réponse.
- **Réponses affichées au fil de l’eau**, avec la mise en forme Markdown : titres, listes, tableaux, citations, et blocs de code munis d’un bouton « Copier ».
- **Modifier un message envoyé** : survolez-le et cliquez sur le crayon, ou appuyez sur ↑ dans la zone de saisie vide. La suite de la conversation est remplacée par une nouvelle réponse.
- **Choix du modèle** dans chaque conversation, depuis un menu placé sous la zone de saisie. Le menu indique ce que sait faire chaque modèle (réflexion, images, outils).
- **Export** d’une conversation en Markdown (⇧⌘E, ou clic droit dans la barre latérale).

**Des réponses plus fiables**

- **Mode raisonnement** : avec les modèles qui raisonnent (qwen3, deepseek-r1, gpt-oss…), le bouton « Réfléchir » active ou coupe la réflexion. Pour gpt-oss, on choisit un effort faible, moyen ou élevé. La réflexion s’affiche à part, avec sa durée (« A réfléchi 12 s »).
- **Profils de réponse** : Équilibré, Rigoureux, Code, Créatif ou Concis. Chaque profil donne ses consignes au modèle et règle sa température. Le profil Rigoureux lui demande de distinguer les faits de ses suppositions et de dire quand il ne sait pas.
- **Vérifier** : sous la dernière réponse, ce bouton demande au modèle de relire sa réponse et d’en corriger les erreurs.
- **Jauge de contexte** : un anneau indique la part de la mémoire de travail du modèle déjà utilisée. Cliquez dessus pour agrandir le contexte. Un bandeau prévient avant qu’Ollama n’oublie le début de la conversation.

**Mémoire**

- **À propos de moi** et **Comment me répondre** (Réglages › Personnalisation) : ce que le modèle doit savoir de vous, envoyé dans chaque conversation.
- **Souvenirs** : dites « Retiens que… » ou « Oublie… » dans un message. En quittant une conversation, le modèle relève aussi les informations durables qui vous concernent. Réglages › Mémoire les affiche tous ; on peut en ajouter ou en supprimer. Ils restent sur votre Mac.

**Au-delà du modèle**

- **Recherche sur Internet** : activez le globe sous la zone de saisie.
  - Les modèles qui gèrent les outils (qwen3, gpt-oss, llama3.1…) cherchent eux-mêmes et lisent les pages utiles. Pour les autres, l’application cherche avant de poser la question.
  - Les sources sont citées [1], [2]… et listées sous la réponse.
  - Il faut soit une clé API Ollama (compte gratuit sur ollama.com, clé gardée dans le trousseau), soit votre propre serveur [SearXNG](https://docs.searxng.org).
- **Vos documents** : PDF, textes, Markdown, Word, RTF, HTML ou code.
  - Pour les joindre, utilisez le trombone ou ⌘O, glissez-les dans la fenêtre, ou choisissez « Ouvrir avec › Ollama Chat » dans le Finder.
  - Les documents courts sont donnés en entier au modèle. Dans les longs, l’application retrouve les passages utiles à chaque question.
  - Un modèle d’indexation (`embeddinggemma`, `nomic-embed-text`…) cherche par le sens ; sans lui, la recherche se fait par mots-clés.
  - Les passages sont cités [D1], [D2]…, avec leur page.
- **Images** : avec un modèle de vision (gemma3, qwen2.5vl, llava…), collez une image (⌘V), glissez-la ou joignez-la.
- **Saisie rapide** : depuis n’importe quelle application, ⌥Espace ouvre un champ pour poser une question. Le raccourci se change dans les réglages.
- **Dictée** : cliquez sur le micro et parlez. La reconnaissance se fait sur le Mac quand la langue le permet.

**Et aussi**

- **Gestion des modèles** : téléchargements (avec leur progression) et suppressions, sans taper `ollama pull` ni `ollama rm`.
- **Apparence** : l’application suit le mode clair ou sombre du système.

## Prérequis

- macOS 14 Sonoma ou plus récent.
- Ollama installé ([ollama.com/download](https://ollama.com/download)). L’application indique quand Ollama n’est pas lancé et propose de l’ouvrir.

## Installation

### Option 1 : télécharger l’application compilée

Chaque modification du dossier `OllamaChat/` déclenche la compilation de l’application sur un Mac de GitHub Actions. L’application obtenue fonctionne sur Apple Silicon comme sur Intel.

1. Connecté à votre compte GitHub, ouvrez la [liste des compilations « Ollama Chat (macOS) »](https://github.com/47n9rmzz6b-lab/CLAUDE/actions/workflows/ollama-chat-macos.yml) (onglet **Actions** du dépôt), puis la dernière exécution marquée d’une coche verte.
2. Tout en bas de la page, section **Artifacts**, téléchargez **Ollama-Chat-macOS**, puis décompressez-le deux fois pour obtenir `Ollama Chat.app`.
3. Glissez `Ollama Chat.app` dans le dossier **Applications**.
4. L’application n’est pas signée par un développeur identifié : macOS refuse de l’ouvrir la première fois.
   - Ouvrez **Réglages Système › Confidentialité et sécurité**, puis cliquez sur **Ouvrir quand même** en face du message concernant Ollama Chat.
   - Vous pouvez aussi lever le blocage en une commande :

     ```sh
     xattr -dr com.apple.quarantine "/Applications/Ollama Chat.app"
     ```

### Option 2 : compiler sur votre Mac

Il faut les outils de développement d’Apple. Xcode suffit, ou simplement les Command Line Tools :

```sh
xcode-select --install
```

Ensuite :

```sh
cd OllamaChat
./scripts/build-app.sh
open "build/Ollama Chat.app"
```

L’application est créée dans `OllamaChat/build/`. Glissez-la dans **Applications** pour la garder. Une application compilée sur votre propre Mac s’ouvre sans avertissement.

Pour développer, `swift run` lance l’application directement, et `swift test` exécute les tests. On peut aussi ouvrir `Package.swift` dans Xcode.

## Utilisation

| Action | Raccourci |
|---|---|
| Envoyer le message | Entrée |
| Aller à la ligne | Maj+Entrée ou Option+Entrée |
| Modifier le dernier message | ↑ dans la zone de saisie vide |
| Nouvelle conversation | ⌘N |
| Joindre des fichiers | ⌘O |
| Exporter la conversation | ⇧⌘E |
| Arrêter la génération | ⌘. |
| Régénérer la dernière réponse | ⌘R |
| Vérifier la dernière réponse | ⇧⌘V |
| Réfléchir avant de répondre (oui/non) | ⌥⌘R |
| Recherche web (oui/non) | ⌥⌘I |
| Profil de réponse | ⌥⌘1 à ⌥⌘5 |
| Gérer les modèles | ⇧⌘M |
| Réglages | ⌘, |
| Saisie rapide, depuis n’importe quelle app | ⌥Espace |

Pour renommer, exporter ou supprimer une conversation, faites un clic droit dessus dans la barre latérale. La touche Suppr supprime aussi la conversation sélectionnée.

Si aucun modèle n’est installé, l’application propose d’en télécharger un. Dans la fenêtre « Modèles », tapez le nom d’un modèle de la [bibliothèque Ollama](https://ollama.com/library) (par exemple `qwen3:8b`, `gemma3`, `llama3.2` ou `mistral`), puis cliquez sur **Télécharger**. Les modèles téléchargés dans le Terminal apparaissent aussi dans la liste, au bout de quelques secondes.

Quelques modèles pour commencer :

- `qwen3:8b` : raisonnement et recherche web ;
- `gemma3` : images ;
- `embeddinggemma` : pour mieux retrouver les passages de vos documents.

## Fonctionnement

L’application ne pilote pas le Terminal. Elle parle directement au serveur Ollama, à l’adresse `http://localhost:11434`, par son [API REST](https://github.com/ollama/ollama/blob/main/docs/api.md). C’est ce même serveur qu’utilise la commande `ollama run`. Les appels utilisés :

- `/api/chat` pour les réponses : en flux, avec la réflexion (`think`), les outils de recherche web, les images et, pour les souvenirs, une réponse au format JSON imposé ;
- `/api/show`, pour savoir ce que sait faire chaque modèle et la taille de contexte qu’il accepte ;
- `/api/embed`, pour indexer les documents ;
- `/api/tags`, pour la liste des modèles ;
- `/api/pull` et `/api/delete`, pour télécharger et supprimer des modèles.

Toutes les requêtes d’une conversation (réponses, titre, souvenirs) utilisent la même taille de contexte, pour qu’Ollama n’ait pas à recharger le modèle entre deux.

Vos données restent sur votre Mac, dans `~/Library/Application Support/OllamaChat/` :

- `conversations.json` : les conversations ;
- `memories.json` : les souvenirs ;
- `attachments/` : les images jointes et le texte découpé des documents.

La clé API de la recherche web est gardée dans le trousseau de macOS. Seules sortent du Mac les recherches web (envoyées au service choisi, avec les pages consultées) et, pour les langues que le Mac ne reconnaît pas lui-même, la dictée, traitée par Apple.

Ollama peut aussi tourner sur une autre machine (un PC avec une carte graphique, par exemple). Lancez-le là-bas avec `OLLAMA_HOST=0.0.0.0 ollama serve`, puis indiquez son adresse dans **Réglages › Général**, par exemple `http://192.168.1.20:11434`.

## Structure du code

```
OllamaChat/
├── Package.swift                  Paquet Swift (macOS 14+, aucune dépendance)
├── Resources/Info.plist           Informations du bundle .app (types de fichiers, micro)
├── scripts/build-app.sh           Compile et assemble « Ollama Chat.app »
├── scripts/make-icon.swift        Dessine l’icône
├── Sources/OllamaChat/
│   ├── App/                       Point d’entrée, menus, réglages, couleurs
│   ├── Models/                    Conversations, messages, profils de réponse
│   ├── Ollama/OllamaClient.swift  Client de l’API Ollama (flux, outils, embeddings)
│   ├── Services/                  Prompt système, mémoire, recherche web, documents,
│   │                              pièces jointes, export, saisie rapide, dictée
│   ├── Store/                     État de l’app : génération, outils, mémoire, modèles
│   ├── Markdown/                  Découpage et affichage du Markdown
│   └── Views/                     Barre latérale, fil de discussion, saisie, fenêtres
└── Tests/                         Tests unitaires (Markdown, client, mémoire, documents, web…)
```
