# Ollama Chat

Ollama Chat est une application Mac native pour discuter avec vos modèles [Ollama](https://ollama.com) dans une fenêtre semblable à celle de l’application Claude, sans passer par le Terminal.

- **Conversations** : elles sont enregistrées et classées par date (Aujourd’hui, Hier, 7 derniers jours…) dans une barre latérale, avec recherche, renommage et suppression. Au lancement, l’application rouvre la dernière conversation affichée.
- **Réponses affichées au fil de l’eau**, avec la mise en forme Markdown : titres, listes, tableaux, citations, et blocs de code munis d’un bouton « Copier ».
- **Modèles qui raisonnent** (qwen3, deepseek-r1…) : leur réflexion s’affiche à part, dans un encadré « Réflexion » qu’on peut déplier.
- **Choix du modèle** dans chaque conversation, depuis un menu placé sous la zone de saisie.
- **Gestion des modèles** : les téléchargements (avec leur progression) et les suppressions se font sans taper `ollama pull` ni `ollama rm`.
- **Reprise en main de la réponse** : on peut arrêter la génération, régénérer la dernière réponse ou copier une réponse.
- **Réglages** : adresse du serveur, instructions système, température, longueur du contexte et police des réponses.
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
| Nouvelle conversation | ⌘N |
| Arrêter la génération | ⌘. |
| Régénérer la dernière réponse | ⌘R |
| Gérer les modèles | ⇧⌘M |
| Réglages | ⌘, |

Pour renommer ou supprimer une conversation, faites un clic droit dessus dans la barre latérale. La touche Suppr supprime aussi la conversation sélectionnée.

Si aucun modèle n’est installé, l’application propose d’en télécharger un. Dans la fenêtre « Modèles », tapez le nom d’un modèle de la [bibliothèque Ollama](https://ollama.com/library) (par exemple `llama3.2`, `gemma3`, `qwen3:8b` ou `mistral`), puis cliquez sur **Télécharger**. Les modèles téléchargés dans le Terminal apparaissent aussi dans la liste, au bout de quelques secondes.

## Fonctionnement

L’application ne pilote pas le Terminal. Elle parle directement au serveur Ollama, à l’adresse `http://localhost:11434`, par son [API REST](https://github.com/ollama/ollama/blob/main/docs/api.md). C’est ce même serveur qu’utilise la commande `ollama run`. Les appels utilisés :

- `/api/chat` en mode flux, pour les réponses ;
- `/api/tags`, pour la liste des modèles ;
- `/api/pull` et `/api/delete`, pour télécharger et supprimer des modèles.

Tout reste sur votre Mac : les conversations sont enregistrées dans `~/Library/Application Support/OllamaChat/conversations.json`.

Ollama peut aussi tourner sur une autre machine (un PC avec une carte graphique, par exemple). Lancez-le là-bas avec `OLLAMA_HOST=0.0.0.0 ollama serve`, puis indiquez son adresse dans **Réglages › Général**, par exemple `http://192.168.1.20:11434`.

## Structure du code

```
OllamaChat/
├── Package.swift                  Paquet Swift (macOS 14+, aucune dépendance)
├── Resources/Info.plist           Informations du bundle .app
├── scripts/build-app.sh           Compile et assemble « Ollama Chat.app »
├── scripts/make-icon.swift        Dessine l’icône
├── Sources/OllamaChat/
│   ├── App/                       Point d’entrée, menus, réglages, couleurs
│   ├── Models/                    Conversations et messages
│   ├── Ollama/OllamaClient.swift  Client de l’API Ollama (flux ligne par ligne)
│   ├── Store/ChatStore.swift      État de l’app, génération, enregistrement
│   ├── Markdown/                  Découpage et affichage du Markdown
│   └── Views/                     Barre latérale, fil de discussion, saisie, fenêtres
└── Tests/                         Tests du parseur Markdown et du client
```
