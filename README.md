# Raccord audio

Petit outil web pour **combiner des fichiers audio** : les mettre bout à bout ou les superposer, régler l’ordre et le volume, écouter le résultat puis le télécharger en MP3 ou en WAV.

Tout le traitement se fait dans le navigateur : les fichiers ne sont envoyés à aucun serveur.

## Ouvrir l’outil

- **Dans Claude** : [Raccord audio](https://claude.ai/artifact/VRamhnddEsNGpBDi28pBdL). Ce lien est privé ; pour que d’autres personnes l’ouvrent, partagez-le depuis le menu Partager de la page. Dans Claude, un fichier audio ne peut pas être téléchargé tel quel : le résultat arrive dans une archive `.zip`, qu’il suffit d’ouvrir pour récupérer le MP3 ou le WAV.
- **Hors de Claude** : ouvrez `index.html` dans un navigateur récent (Chrome, Edge, Firefox, Safari). Le fichier `.mp3` ou `.wav` est alors téléchargé directement. L’export MP3 demande une connexion Internet (l’encodeur est chargé depuis jsDelivr) ; l’export WAV fonctionne hors ligne.

## Mode d’emploi

1. Ajoutez vos fichiers avec le bouton ou par glisser-déposer. Plusieurs fichiers ajoutés d’un coup sont classés par nom (« partie 2 » avant « partie 10 »).
2. Choisissez le mode :
   - **Bout à bout** : les pistes s’enchaînent, avec un raccord direct, un silence ou un fondu enchaîné de la durée choisie.
   - **Superposer** : toutes les pistes démarrent ensemble (une voix sur une musique, par exemple). L’option « Arrêter à la fin de la piste 1 » coupe le mélange à la fin de la première piste ; les autres s’effacent en fondu sur 2 secondes.
3. Réglez l’ordre avec les flèches et le volume de chaque piste (de −24 à +12 dB). « Égaliser les volumes » ramène chaque piste à un niveau sonore comparable.
4. Écoutez le résultat, puis téléchargez-le en **MP3** (192 kbit/s en stéréo, 128 kbit/s en mono) ou en **WAV** 16 bits.

Le résultat est en 44,1 kHz, en stéréo dès qu’une piste l’est. Si le mélange dépasse −1 dBFS, l’ensemble est baissé d’autant pour éviter la saturation.

## Formats et limites

- Formats d’entrée : ceux que le navigateur sait décoder. MP3, WAV et FLAC passent partout ; M4A/AAC et OGG/Opus dépendent du navigateur et du système. Un fichier illisible est signalé dans la liste sans bloquer les autres.
- Les fichiers sont décodés en mémoire : pour plusieurs heures d’audio, préférez Audacity ou ffmpeg.

## Autres outils

- **Audacity** (gratuit, Windows, macOS, Linux) : pour un vrai montage (couper, déplacer, effets). <https://www.audacityteam.org>
- **ffmpeg**, en ligne de commande :

```sh
# Bout à bout (les formats peuvent être différents)
ffmpeg -i partie1.mp3 -i partie2.m4a -i partie3.wav \
  -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[a]" -map "[a]" fusion.mp3

# Fondu enchaîné de 2 secondes entre deux fichiers
ffmpeg -i a.mp3 -i b.mp3 -filter_complex "[0:a][1:a]acrossfade=d=2[a]" -map "[a]" fondu.mp3

# Voix + musique baissée à 30 %, arrêt à la fin de la voix
ffmpeg -i voix.m4a -i musique.mp3 \
  -filter_complex "[1:a]volume=0.3[m];[0:a][m]amix=inputs=2:duration=first[a]" -map "[a]" mix.mp3
```

## Détails techniques

Un seul fichier, `index.html`, sans dépendance à installer ni étape de compilation. Le décodage passe par l’API Web Audio du navigateur, le mixage est fait en JavaScript et l’encodage MP3 par [lamejs](https://github.com/zhuker/lamejs) (LGPL-3.0), chargé à la demande. La partie comprise entre les marqueurs `artifact:start` et `artifact:end` est celle publiée comme artefact Claude.
