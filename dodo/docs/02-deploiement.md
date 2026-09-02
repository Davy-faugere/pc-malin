# Déploiement — d'abord le PC d'essai, ensuite les autres

Cette procédure est conçue pour que **rien ne s'éteigne** tant que vous n'avez pas
validé chaque étape. Le mode par défaut est la **simulation**.

---

## 0. Prérequis à vérifier avant tout

| Point | Vérification | Pourquoi |
|---|---|---|
| Windows 10 ou 11 | `winver` | Windows PowerShell 5.1 et le Planificateur de tâches sont requis |
| Compte enfant **standard** | `Get-LocalGroupMember -SID 'S-1-5-32-544'` | Un administrateur peut tout désactiver en trois clics |
| Vous avez un mot de passe administrateur que l'enfant ne connaît pas | — | C'est le seul vrai verrou |
| Voix française installée *(recommandé)* | voir §4 | Sinon le message sera lu par une voix anglaise, ou remplacé par un WAV |

Retirer l'enfant des administrateurs, si besoin :

```powershell
Get-LocalGroupMember -SID 'S-1-5-32-544'
Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member 'Malo'
```

---

## 1. Récupérer les fichiers sur le PC d'essai

Copiez le dossier `dodo\` (sous-dossiers `src\` et `tests\`) sur le PC d'essai,
par exemple dans `C:\Temp\dodo`.

---

## 2. Installer en mode simulation

Ouvrez **PowerShell en tant qu'administrateur**, puis :

```powershell
cd C:\Temp\dodo\src
powershell -ExecutionPolicy Bypass -File .\Install-Dodo.ps1
```

L'installateur :

1. refuse de continuer sans droits administrateur ;
2. **affiche la liste des administrateurs locaux** — relisez-la ;
3. crée `C:\ProgramData\Dodo` (`bin`, `etc`, `var`, `logs`, `media`) ;
4. **coupe l'héritage des droits** : SYSTEM et Administrateurs en contrôle total,
   groupe Utilisateurs en lecture seule ;
5. récupère le calendrier zone C officiel ;
6. enregistre les deux tâches planifiées ;
7. relit tout ce qu'il vient d'écrire et signale la moindre anomalie.

> **`dryRun` est à `true`** : à ce stade, aucune extinction réelle n'est possible.

---

## 3. Vérifier l'état

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\Dodo\bin\Get-DodoStatus.ps1
```

Contrôlez trois choses :

- **Calendrier : fiable = OUI** et les dates de vacances correspondent au calendrier
  officiel (comparez avec `education.gouv.fr`) ;
- le **prévisionnel des 14 prochaines nuits** affiche `school` (21:00) ou
  `holiday` (23:00) comme vous l'attendez ;
- les deux tâches sont `Ready` avec `repetition=PT1M`.

---

## 4. Vérifier le son

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\Dodo\bin\Show-DodoWarning.ps1 -ListVoices
powershell -ExecutionPolicy Bypass -File C:\ProgramData\Dodo\bin\Show-DodoWarning.ps1 -Force -ForceMinutes 5
```

La seconde commande doit **parler** et afficher la fenêtre orange.

**S'il n'y a aucune voix française** — c'est fréquent sur Windows 11, dont les voix
« modernes » (*Speech_OneCore*) ne sont pas visibles par l'interface `System.Speech`
utilisée ici. Deux options, toutes deux valables :

- *Paramètres → Heure et langue → Voix → Ajouter des voix →* **Français (France)**,
  puis redémarrer et refaire `-ListVoices` ;
- ou, plus simple et parfaitement fiable : **enregistrez vous-même les messages**
  (Enregistreur vocal de Windows, export en `.wav`) et déposez-les dans
  `C:\ProgramData\Dodo\media\` sous les noms `warning.wav` et `shutdown.wav`.
  Ils ont la priorité sur la synthèse vocale.

Les textes prononcés se modifient dans `C:\ProgramData\Dodo\etc\dodo.messages.json`
(fichier en UTF-8, accents autorisés ; jetons `{minutes}` et `{name}`).

---

## 5. Recette bout-en-bout

```powershell
cd C:\Temp\dodo\tests
powershell -ExecutionPolicy Bypass -File .\Test-DodoE2E.ps1
```

Six phases s'enchaînent (≈ 2 minutes) :

| Phase | Ce qui est prouvé |
|---|---|
| `preflight` | Droits, **les scripts déployés sont bit à bit identiques aux sources**, voix disponibles |
| `logic` | 118 assertions du noyau : horaires, bascules de nuit, vacances, changements d'heure |
| `calendar` | Récupération réelle **et** repli : cache retiré → un soir de vacances repasse en 21:00 |
| `security` | Le groupe Utilisateurs ne peut écrire ni dans `bin`, ni dans `etc`, ni dans `var` ; la tâche tourne bien sous SYSTEM |
| `tasks` | Attente de 75 s : la tâche se déclenche **toute seule** et se termine en code 0 |
| `evening` | **Une soirée entière rejouée en une minute** : les 4 préavis sonnent et s'affichent, puis l'extinction est journalisée (simulée) |

La phase `evening` fait réellement apparaître les fenêtres et entendre la voix :
c'est le moment de vérifier que le message vous convient.

### 5b. Persistance après redémarrage

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-DodoE2E.ps1 -Phase boot
# attendre 2 minutes, redémarrer, rouvrir une session administrateur
powershell -ExecutionPolicy Bypass -File .\Test-DodoE2E.ps1 -Phase bootcheck
```

Prouve que la règle se réapplique **seule en moins de 3 minutes** après un
redémarrage — toujours en simulation, le poste ne s'éteint pas.

### 5c. Une vraie extinction, une seule fois

À faire **en journée**, loin de la fenêtre normale :

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-DodoE2E.ps1 -Phase real -IReallyWantToShutDown -InMinutes 12
```

Le test refuse de démarrer si la règle normale se déclenche dans moins de 22 minutes.
Vous entendrez les préavis à T-10, T-5, T-2, T-1, puis le poste s'éteindra pour de bon.

> La fenêtre d'essai est **à usage unique** : l'agent la retire de la configuration au
> moment même où il émet l'ordre d'extinction. Aucun risque de boucle au redémarrage.

Pour tout annuler pendant le décompte, depuis une session administrateur :

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\Dodo\bin\Add-DodoException.ps1 -Minutes 60 -Reason "annulation du test"
```

---

## 6. Passer en production sur le PC d'essai

```powershell
cd C:\Temp\dodo\src
powershell -ExecutionPolicy Bypass -File .\Install-Dodo.ps1 -Production -ExemptUsers 'Papa'
```

`-ExemptUsers` : tant qu'une session est ouverte par l'un de ces comptes, le poste
ne s'éteint pas (utile si vous travaillez tard sur la machine).

---

## 7. Interdire le partage de connexion (portable uniquement)

```powershell
# 1. Relever le nom exact du Wi-Fi de la maison
netsh wlan show interfaces

# 2. N'autoriser que celui-là, et bloquer toute nouvelle carte réseau
powershell -ExecutionPolicy Bypass -File .\Install-Dodo.ps1 -Production `
    -AllowedSsid 'NOM-EXACT-DU-WIFI' -EnableAdapterGuard

# 3. Vérifier
netsh wlan show filters
```

Deux verrous complémentaires :

- **Filtre SSID** (`netsh wlan add filter … denyall`) : le portable ne peut se
  connecter qu'au Wi-Fi de la maison. Le point d'accès du téléphone devient
  inatteignable. Modifier ces filtres exige les droits administrateur.
- **Garde-cartes réseau** : la liste blanche est constituée des cartes **réellement
  présentes** au moment de l'installation. Toute carte apparaissant ensuite — partage
  USB du téléphone (« Remote NDIS »), partage Bluetooth, clé 4G — est désactivée dans
  la minute et l'événement est journalisé.

> À relancer avec `-EnableAdapterGuard` après tout changement matériel légitime
> (nouvelle carte Wi-Fi, dock USB Ethernet), sinon la nouvelle carte sera désactivée.

---

## 8. Déployer sur les autres postes

Une fois la recette validée sur le PC d'essai :

```powershell
# Poste fixe (Ethernet) — pas de filtre Wi-Fi à poser
.\Install-Dodo.ps1 -Production -ExemptUsers 'Papa'

# Portable
.\Install-Dodo.ps1 -Production -ExemptUsers 'Papa' -AllowedSsid 'NOM-DU-WIFI' -EnableAdapterGuard
```

Puis, sur **chaque** poste :

```powershell
.\Test-DodoE2E.ps1 -Phase preflight,logic,calendar,security,tasks
Get-DodoStatus.ps1
```

La phase `evening` exige le mode simulation ; sur un poste déjà en production,
lancez-la avant `-Production`, ou contentez-vous des cinq phases ci-dessus.

---

## 9. Désinstaller

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\Dodo\bin\Uninstall-Dodo.ps1
```

Retire les tâches, les filtres Wi-Fi, réactive les cartes réseau désactivées, supprime
les marqueurs dans les profils et le dossier d'installation.
Ajoutez `-KeepLogs` pour conserver les journaux.
