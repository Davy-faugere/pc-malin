# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/) · Versioning : [SemVer](https://semver.org/lang/fr/)

## [1.3.0] - 2026-09-02

### Ajouté
- **Dodo** — couvre-feu automatique des postes de la maison (`dodo/`), installable indépendamment de PC Malin
  - extinction à **21h00** en période scolaire et **23h00** pendant les vacances scolaires **zone C**, réutilisation à partir de 06h30
  - **préavis vocal et fenêtre au premier plan** à 10, 5, 2 et 1 minute ; message parlé personnalisable (synthèse vocale ou fichiers WAV enregistrés par le parent)
  - **résistance au redémarrage** : déclencheur au démarrage + répétition d'une minute, sous le compte SYSTEM
  - **calendrier des vacances zone C récupéré automatiquement** depuis l'API Open Data du ministère de l'Éducation nationale, avec repli sur la règle la plus stricte si le calendrier est indisponible, périmé ou illisible
  - **blocage du partage de connexion** sur le portable : filtre SSID Wi-Fi et désactivation de toute carte réseau non recensée
  - dérogation ponctuelle accordée par un parent (`Add-DodoException.ps1`)
  - journal horodaté local et journal Windows *Application* (source `Dodo`)
  - **118 tests de logique hors ligne** et une **recette bout-en-bout** en 8 phases, dont une soirée complète rejouée en une minute et un test de vraie extinction à usage unique

### Précision
- Dodo n'est pas embarqué dans `PC-Malin.exe` / `PC-Malin.cmd` : c'est un outil distinct, déployé par ses propres scripts

## [1.2.0] - 2026-07-18

### Ajouté
- **Analyser mon PC** : 10 contrôles en lecture seule (espace et santé du disque, SSD/disque dur, mémoire installée et utilisée, programmes gourmands, programmes au démarrage, mises à jour Windows, antivirus/pare-feu, dernier redémarrage, dossiers qui débordent) avec **note sur 20** et conseil clair pour chaque point
- **Rapport d'analyse en PDF** (bouton « Enregistrer le rapport »), enregistré dans Documents — repli HTML si Edge est absent
- Nouvelle tuile « Analyser mon PC » sur la page d'accueil

### Précision
- L'analyse ne modifie rien et n'envoie rien : tout reste sur l'ordinateur

## [1.0.0] - 2026-07-13

### Ajouté
- Quatre espaces : Mon ordinateur, Faire le ménage, Bilan de santé, Conseils
- Nettoyage sûr : corbeille, fichiers temporaires, cache Windows Update, journaux — jamais les fichiers personnels
- Bilan de santé : espace disque, mémoire, dernier redémarrage, connexion Internet (vert / orange / rouge + conseil)
- Page d'accueil à tuiles, interface claire en français simple
- Installation optionnelle (raccourci Bureau) ou utilisation sans installation
- Deux formats : `PC-Malin.exe` (lanceur natif, aucune console) et `PC-Malin.cmd` (script lisible auto-extractible)
- Icône embarquée, journal local des actions
