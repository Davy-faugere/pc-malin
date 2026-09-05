# Dodo — couvre-feu automatique des PC de la maison

Éteint les ordinateurs de l'enfant à heure fixe, avec **préavis vocal et rappels
à l'écran 10 minutes avant**, en distinguant **période scolaire** et **vacances
scolaires zone C**, et en **résistant au redémarrage**.

| | Période scolaire | Vacances zone C |
|---|---|---|
| Extinction | **21h00** | **23h00** |
| Réutilisable à partir de | **06h30** | **06h30** |

Fonctionne à l'identique sur un **portable Wi-Fi** et sur un **poste fixe Ethernet** :
la décision est prise localement, sans dépendre du réseau.

---

## En bref

```
dodo/
  build/
    build.sh                  construit l'exe et le cmd (python3, zip, mono-mcs)
    launcher.cs               lanceur natif : élévation UAC + extraction
    header.cmd                en-tête de la version .cmd auto-extractible
  src/
    Assistant-Dodo.ps1        assistant graphique (embarqué dans l'exe)
    DodoCore.ps1              noyau de décision — 100 % pur, sans effet de bord
    DodoRuntime.ps1           fichiers, cache calendrier, journal
    Invoke-DodoEnforce.ps1    agent SYSTEM : c'est lui, et lui seul, qui éteint
    Show-DodoWarning.ps1      agent session utilisateur : voix + fenêtre d'alerte
    DodoSpeech.ps1            moteur vocal : voix modernes de Windows 11 (OneCore) + SAPI5
    Get-DodoStatus.ps1        état complet et prévisionnel nuit par nuit
    Add-DodoException.ps1     dérogation ponctuelle accordée par un parent
    Install-Dodo.ps1          installation / mise à jour
    Uninstall-Dodo.ps1        retrait complet
    run-notify-hidden.vbs     lanceur silencieux (aucune console qui clignote)
    dodo.config.json          modèle de configuration
    dodo.messages.json        textes prononcés et affichés (UTF-8, modifiables)
  tests/
    Test-DodoLogic.ps1        118 assertions, hors ligne, exécutables partout
    Test-DodoE2E.ps1          recette bout-en-bout sur le poste
  docs/
    01-solutions.md           trois solutions comparées, avec schémas
    02-deploiement.md         du PC d'essai au déploiement
    03-exploitation.md        exploitation, réglages, limites, diagnostic
```

## Démarrage rapide — double-clic

**`Dodo-Installateur.exe`** : Windows demande l'autorisation, l'assistant s'ouvre.
Aucune commande à taper.

L'assistant fait tout : il liste les comptes locaux, signale si l'enfant est
administrateur (et propose de l'en retirer d'un clic), détecte le Wi-Fi de la
maison et les cartes réseau, puis installe. Trois boutons complètent l'écran :
**Voir l'état**, **Tester une soirée**, **Désinstaller**.

Par défaut il installe en **simulation** : rien ne s'éteint tant que vous n'avez
pas basculé sur *Mise en service*.

> `Dodo-Installateur.cmd` fait exactement la même chose, en fichier texte lisible
> dans le Bloc-notes avant lancement — même logique que PC Malin.

<details>
<summary>Ligne de commande, pour un déploiement en série</summary>

```powershell
# PowerShell EN ADMINISTRATEUR
cd .\dodo\src
.\Install-Dodo.ps1                                    # simulation
.\Install-Dodo.ps1 -Production -ExemptUsers 'Papa' `
    -AllowedSsid 'MON-WIFI' -EnableAdapterGuard        # mise en service, portable
.\Get-DodoStatus.ps1
cd ..\tests ; .\Test-DodoE2E.ps1
```
</details>

Procédure détaillée : **[docs/02-deploiement.md](docs/02-deploiement.md)**.

---

## Ce qui est garanti — et comment c'est vérifié

| Exigence | Mécanisme | Test qui le prouve |
|---|---|---|
| Extinction réelle | `shutdown /s /f` émis par le compte SYSTEM | `-Phase real` |
| Préavis vocal + rappels | 10 / 5 / 2 / 1 min, **voix française de Windows 11** (OneCore) ou WAV enregistré, fenêtre au premier plan | `-Phase evening` |
| Texte écrit par le parent, répété | Message saisi dans l'assistant, redit toutes les N secondes pendant l'affichage | `-SpeakText`, recette Windows |
| Résiste au redémarrage | Déclencheur « au démarrage » + répétition d'une minute | `-Phase boot` / `-Phase bootcheck` |
| Vacances zone C automatiques | API Open Data `data.education.gouv.fr` | `-Phase calendar` |
| Jamais d'ouverture accidentelle | Calendrier absent / périmé / illisible → **repli sur 21h00** | `-Phase calendar` |
| Non contournable par l'enfant | Héritage des droits coupé, groupe Utilisateurs en lecture seule, tâche sous SYSTEM | `-Phase security` |
| Pas de partage de connexion | Filtre SSID `netsh wlan` + désactivation de toute carte réseau non recensée | `Get-DodoStatus.ps1` |
| Installation sans jargon | Assistant graphique auto-élevé, embarqué dans un seul `.exe` | double-clic |

Le noyau de décision est **entièrement séparé** des effets de bord : `DodoCore.ps1`
n'éteint rien, n'écrit rien, ne va pas sur le réseau. C'est ce qui permet de rejouer
118 cas — bascules de minuit, veille de rentrée, changements d'heure légale, panne de
calendrier — en une seconde et sans risque.

## Prérequis non négociable

**Le compte de l'enfant doit être un compte standard, pas administrateur.**
Sans cela, aucune solution logicielle ne tient. `Install-Dodo.ps1` et
`Test-DodoE2E.ps1 -Phase security` affichent la liste des administrateurs locaux à
chaque exécution pour que ce point reste sous contrôle.

Limites connues et risques résiduels — mode sans échec, démarrage USB, etc. — sont
listés sans complaisance dans
**[docs/03-exploitation.md](docs/03-exploitation.md#limites-connues-et-risques-résiduels)**.
