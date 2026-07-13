# 🧹 PC Malin

**L'entretien facile de votre ordinateur Windows** — gratuit, un seul fichier, en français simple.

![PC Malin](assets/pcmalin_preview.png)

## C'est quoi ?

Un petit outil qui aide n'importe qui à garder son PC en forme, sans être informaticien :

| Espace | Ce qu'il fait |
|---|---|
| **Mon ordinateur** | La carte d'identité du PC : nom, modèle, Windows, RAM, jauge disque |
| **Faire le ménage** | Corbeille, fichiers temporaires, restes de mises à jour — avec le total d'espace récupéré |
| **Bilan de santé** | 4 contrôles (disque, mémoire, redémarrage, Internet) en vert / orange / rouge, avec un conseil clair |
| **Conseils** | Les 6 réflexes qui évitent 80 % des « ça rame » |

**Vos documents, photos et fichiers personnels ne sont jamais touchés.** PC Malin ne supprime que les fichiers « poubelle » de Windows.

Pas de pub, pas de collecte de données, pas de connexion Internet requise. Et tout le code est lisible ici même — c'est le principe.

## Installation

Deux formats au choix, même contenu — voir [Releases](../../releases) :

- **`PC-Malin.exe`** — le plus simple : double-clic, autorisation Windows, c'est parti.
  > Au premier lancement d'un fichier téléchargé, Windows SmartScreen peut afficher un avertissement (l'exe n'est pas signé par un certificat commercial). Cliquez sur *Informations complémentaires* → *Exécuter quand même*. Le code source de ce que vous exécutez est exactement ce que vous lisez dans ce dépôt.
- **`PC-Malin.cmd`** — la version « transparente » : un fichier texte que vous pouvez ouvrir dans le Bloc-notes et lire intégralement avant de le lancer.

Au premier lancement, PC Malin propose de s'installer (raccourci sur le Bureau) ou de fonctionner sans rien installer.

**Compatibilité** : Windows 10 et 11. Aucune dépendance à installer.

**Désinstallation** : supprimez le raccourci du Bureau et le dossier `C:\ProgramData\PC Malin`. C'est tout.

## Structure du dépôt

```
src/
  pcmalin.ps1    # L'application (PowerShell + WinForms) — tout est là
  launcher.cs    # Lanceur natif de l'exe (extraction + exécution sans console)
  header.cmd     # En-tête batch de la version .cmd auto-extractible
assets/
  pcmalin.ico    # Icône (16→64 px)
docs/
  guide.html     # Guide d'utilisation grand public
build/
  build.sh       # Construit PC-Malin.cmd et PC-Malin.exe
```

## Construire soi-même

Sous Linux/WSL (ou tout environnement avec `mono-mcs` et Python 3) :

```bash
./build/build.sh
# Produit : dist/PC-Malin.cmd et dist/PC-Malin.exe
```

La version `.cmd` peut aussi être assemblée à la main : contenu de `src/header.cmd`, puis le marqueur `ZZ_PSSTART_ZZ` est suivi de `src/pcmalin.ps1`.

## Contribuer

Les idées et corrections sont bienvenues — c'est le but du dépôt.

- **Issues** : un bug, un texte pas clair, une idée d'espace ? Ouvrez une issue.
- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/fr/) — `feat(menage): …`, `fix(bilan): …`, `docs(guide): …`
- **Versions** : [SemVer](https://semver.org/lang/fr/) — voir [CHANGELOG.md](CHANGELOG.md)
- **Règle d'or** : tout doit rester compréhensible par un non-informaticien. Vocabulaire simple, messages rassurants, jamais de jargon dans l'interface.
- **Règle de sécurité** : l'outil ne touche jamais aux fichiers personnels de l'utilisateur, ne se connecte jamais à Internet (hors ouverture de Windows Update à la demande), ne collecte rien.

## Licence

[MIT](LICENSE) — utilisez, modifiez, partagez librement.

---

Créé par **Davy Faugère** — consultant IT/OT · [faugere-davy.fr](https://faugere-davy.fr)
