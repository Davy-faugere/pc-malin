# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/) · Versioning : [SemVer](https://semver.org/lang/fr/)

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
