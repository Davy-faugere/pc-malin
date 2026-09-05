# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/) · Versioning : [SemVer](https://semver.org/lang/fr/)

## [1.4.5] - 2026-09-05

### Modifié
- **Interface modernisée.** L'assistant est net sur les écrans haute définition (il était agrandi à partir d'une image basse résolution, donc flou). Les cadres gravés hérités de Windows XP laissent place à des cartes blanches à filet clair, les boutons sont plats, à coins arrondis, avec effet de survol, et l'en-tête ainsi que le journal ont été repris. Aucun changement de comportement : mêmes champs, mêmes réglages, mêmes actions

## [1.4.4] - 2026-09-05

### Corrigé
- **LE POSTE NE S'ÉTEIGNAIT JAMAIS.** Les préavis vocaux se déclenchaient, la fenêtre s'affichait, puis rien. Cause : `Start-Process` colle les arguments les uns aux autres **sans guillemets**. Le message d'extinction contenant des espaces, la commande devenait `shutdown /s /f /t 30 /c Il est l heure de dormir …` — une dizaine d'arguments inconnus. `shutdown.exe` refusait la commande et renvoyait le code 1. La ligne de commande est désormais construite avec ses guillemets.
- Ce chemin n'avait jamais été exercé nulle part : en simulation l'agent s'arrête juste **avant** l'appel à `shutdown.exe`. La recette Windows commande maintenant une **vraie** extinction, avec un délai de 600 s, vérifie auprès de Windows qu'elle est bien programmée (`shutdown /a` ne réussit que dans ce cas), puis l'annule

## [1.4.3] - 2026-09-05

### Corrigé
- **L'agent d'extinction pouvait ne rien faire sans laisser la moindre trace.** Sur la plupart de ses chemins de sortie il s'arrêtait en silence, et une erreur non prévue le tuait sans écrire une ligne. Résultat : quand le poste ne s'éteignait pas, le journal était vide — c'est-à-dire illisible exactement au moment où il fallait comprendre pourquoi. Désormais :
  - un filet global journalise toute erreur non prévue, avec le numéro de ligne, dans le journal Dodo **et** dans le journal Windows ;
  - chaque décision est écrite : hors fenêtre (avec la date de la prochaine extinction), Dodo désactivé, dérogation en cours, compte exempté à l'écran, extinction déjà commandée ;
  - ces lignes ne sont écrites qu'au **changement** de décision, pas à chaque minute : le journal reste lisible au lieu de se remplir de 1440 lignes identiques par jour.
- Un message d'extinction personnalisé illisible ou vide ne peut plus empêcher l'extinction : le texte par défaut prend le relais et l'incident est journalisé

## [1.4.2] - 2026-09-04

### Corrigé
- **Le poste ne s'éteignait jamais sur le profil de l'enfant, sans qu'aucune erreur ne le signale.** Deux causes, indépendantes, toutes deux corrigées :

  1. **Le compte de l'enfant pouvait être exempté — et l'était d'office s'il était administrateur.** L'assistant pré-cochait *tous* les comptes administrateurs dans la liste des adultes exemptés, y compris celui de l'enfant. L'agent journalisait alors « Extinction suspendue : session ouverte par le compte exempté 'Malo' » et n'éteignait rien. Exempter celui que la règle vise annule la règle : le compte désigné comme celui de l'enfant est désormais retiré de la liste des exemptés par l'installateur lui-même, donc sur **tous** les chemins d'appel (assistant, fiche de réponses, ligne de commande), avec un avertissement visible.

  2. **Une session d'adulte laissée ouverte en arrière-plan suspendait l'extinction indéfiniment.** La présence d'un adulte était déduite de ses processus `explorer.exe`. Or avec le changement rapide d'utilisateur, la session d'un parent reste ouverte — et son `explorer.exe` tourne — alors qu'il n'est plus devant le poste. Il suffisait donc qu'un parent ait oublié de fermer sa session pour que le couvre-feu ne s'applique plus jamais. Seul le compte réellement **ouvert à l'écran** (session attachée à la console) suspend maintenant l'extinction ; si cette session est indéterminable, l'ancienne règle, plus prudente, s'applique en repli.

### Ajouté
- `Get-DodoStatus.ps1` affiche la ligne **« Session à l'écran »** : le compte présent devant la machine et s'il est exempté ou non. C'est la ligne qui répond directement à « pourquoi le poste ne s'éteint pas »

## [1.4.1] - 2026-09-04

### Corrigé
- **La fenêtre « Horaires et vacances » plantait au clic sur *Valider*** dès que l'heure d'extinction saisie était antérieure à l'heure de réveil — le cas normal quand on saisit une plage courte pour tester (par exemple extinction 15:30, réveil 16:00). Au lieu du message d'explication attendu, Windows affichait « Une exception non gérée s'est produite… Erreur lors de la mise en forme d'une chaîne : l'index (de base zéro) doit être supérieur ou égal à zéro et inférieur à la taille de la liste des arguments ».

  Cause : dans la liste d'arguments d'une **méthode**, les virgules séparent les arguments de la méthode, pas les valeurs de l'opérateur `-f`. Écrit sans parenthèses autour du format, `[MessageBox]::Show("… {1} …" -f $a, $b, 'Dodo', 'OK')` ne transmet que `$a` à `-f`, et le jeton `{1}` échoue — à l'exécution seulement, jamais à l'analyse syntaxique

### Ajouté
- Contrôle statique de **toutes** les chaînes formatées des sources et des recettes : l'arbre syntaxique de chaque `.ps1` est relu et, pour chaque `-f` dont le format est littéral, le plus grand jeton `{n}` est comparé au nombre de valeurs fournies. La règle est stricte et assumée : au-delà d'un jeton, la droite doit être une liste littérale séparée par des virgules — c'est exactement ce qui disparaît quand on oublie les parenthèses. Le contrôle a été vérifié dans les deux sens (il tombe sur le défaut ci-dessus en le nommant à la ligne près, il passe une fois corrigé)

## [1.4.0] - 2026-09-02

### Ajouté
- **Voix de Windows 11 enfin utilisée.** Windows expose deux catalogues de voix qui ne se voient pas entre eux : les voix *OneCore* (celles de *Paramètres → Heure et langue → Voix*) et les voix *SAPI5* classiques. Sur une installation française, **les voix françaises sont toujours du premier jeu**, invisible pour `System.Speech` — l'interface utilisée jusqu'ici. Le message était donc lu par une voix anglaise, ou pas lu du tout. Nouveau `DodoSpeech.ps1` : les voix modernes sont atteintes par l'API WinRT `Windows.Media.SpeechSynthesis`, les deux catalogues sont fusionnés, et `-ListVoices` les affiche avec leur moteur
- **Texte écrit par le parent.** Assistant → *Message parlé et voix…* : les trois messages (préavis, dernière minute, extinction) se saisissent dans l'interface, avec les jetons `{minutes}` et `{name}`. Plus besoin d'éditer un fichier JSON
- **Répétition pendant le décompte.** Le message est redit toutes les `speech.repeatEverySeconds` secondes tant que la fenêtre d'alerte est affichée. La synthèse n'a lieu qu'une fois : le WAV produit est conservé et rejoué, les répétitions sont instantanées. Aucune diffusion n'est programmée à l'instant exact de la fermeture, elle serait coupée
- Choix de la voix, du débit et du volume dans l'assistant, avec un bouton **Écouter** qui passe par le moteur réel — ce qu'on entend au réglage est ce qu'on entendra le soir
- Coupure complète de la voix en un clic (*« Annoncer le message à voix haute »* décoché, ou `speech.engine = "off"`)
- `Show-DodoWarning.ps1 -SpeakText "…"` : essai d'un texte quelconque en ligne de commande, avec restitution de la voie réellement employée
- **26 assertions hors ligne** sur les réglages de voix et la cadence de répétition, et une **phase d'intégration Windows** qui exerce la synthèse réelle : énumération des deux catalogues, conversion de débit, synthèse d'un WAV dont l'en-tête `RIFF` et la taille sont vérifiés, et repli complet sans exception

### Corrigé
- Le rapport `-ValidateOnly` de l'installateur annonçait « 1 période » et un SSID fantôme quand rien n'était fourni : `@($null)` compte un élément, pas zéro. Le chemin d'installation réel n'était pas affecté, mais un diagnostic qui compte faux induit en erreur

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
  - **`Dodo-Installateur.exe`** — assistant graphique auto-élevé (UAC), sans aucune commande à taper : choix du compte de l'enfant avec alerte et retrait des droits administrateur en un clic, comptes adultes exemptés, détection du Wi-Fi de la maison et des cartes réseau, mode simulation ou mise en service, puis boutons *Voir l'état*, *Tester une soirée* et *Désinstaller*. Variante `.cmd` lisible dans le Bloc-notes, comme PC Malin
  - **horaires et périodes de vacances saisissables à la main** dans l'assistant : le dispositif reste opérationnel sur un poste sans accès à l'API du ministère (réseau d'entreprise, filtrage), les périodes saisies faisant alors autorité
  - **141 assertions de logique hors ligne**, rejouées sous Windows PowerShell 5.1 comme sous PowerShell 7, une **recette d'intégration en 9 phases sur Windows réel** (47 contrôles : installation, ACL, tâches, agents, soirée simulée, déclenchement spontané, désinstallation et retour à l'état initial) exécutée en intégration continue avant toute publication, et une **recette bout-en-bout** manuelle dont une soirée complète rejouée en une minute et un test de vraie extinction à usage unique

### Corrigé
- `Install-Dodo.ps1` : `icacls /inheritance:r /T` était appliqué **avant** `/grant`, ce qui vidait les droits de la racine, faisait perdre l'accès au processus et échouait en « Accès refusé » sur les sous-dossiers. Les droits explicites sont désormais posés d'abord, l'héritage n'est coupé que sur la racine, et le résultat est vérifié par lecture effective des ACL
- **Enregistrement des tâches refusé par le planificateur** (`HRESULT 0x80041318`, Windows 11) : une durée de répétition infinie se sérialisait en `P99999999DT23H59M59S`, valeur rejetée. Le déclencheur est désormais créé sans durée, et l'enregistrement suit une cascade de trois formes (déclencheur répété, enregistrement en deux temps, `schtasks /SC MINUTE /MO 1`) dont le résultat est **relu et vérifié** après création
- **Débordement de paramètres vers `-InstallPath`** : `powershell.exe -File` ne réinterprète pas les guillemets PowerShell, si bien qu'un nom de carte réseau contenant une espace était scindé et le reste affecté au paramètre positionnel suivant — une seule cause pour trois symptômes (chemin d'installation corrompu, compte porteur de guillemets, cartes tronquées). Les réglages transitent désormais par une **fiche de réponses JSON**, avec garde-fous sur le chemin et le nom de compte
- **Le filtre Wi-Fi rendait tous les réseaux invisibles** : un `denyall` posé avec une autorisation ne correspondant à aucun SSID masquait le réseau de la maison, et la désinstallation ne le retirait pas car elle lisait sa configuration au mauvais endroit. Le filtre n'est plus jamais appliqué en mode simulation ni sans autorisation valide, et le retrait du `denyall` à la désinstallation est désormais **inconditionnel**
- **Partage de connexion par Bluetooth PAN** : les cartes Bluetooth, Remote NDIS et assimilées sont exclues par défaut de la liste blanche
- **Contrôle des droits faussement au vert** : le test utilisait le masque composite `Modify`, qui contient les bits de lecture — tout compte en lecture seule était donc déclaré en écriture. Le contrôle repose maintenant sur les **bits élémentaires d'écriture**, dans une fonction unique partagée par l'installateur et la recette
- `Show-DodoWarning.ps1` masquait toutes ses erreurs derrière un `exit 0`, rendant tout diagnostic impossible : les erreurs sont affichées en session interactive et un mode `-Diagnose` restitue voix disponibles, chemins résolus et état courant
- `shutdown /a` écrit sur la sortie d'erreur quand aucune extinction n'est en cours (code 1116, cas normal) : la sortie est redirigée pour ne plus faire échouer la désinstallation

### Précision
- Dodo n'est pas embarqué dans `PC-Malin.exe` / `PC-Malin.cmd` : c'est un outil distinct, avec son propre installateur

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
