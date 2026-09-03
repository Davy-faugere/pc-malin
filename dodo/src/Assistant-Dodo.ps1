#Requires -Version 5.1
<#
    Assistant-Dodo.ps1 - Assistant graphique d'installation du couvre-feu.

    C'est ce script qui est embarque dans Dodo-Installateur.exe : l'utilisateur
    ne tape aucune commande. Il choisit le compte de l'enfant, le Wi-Fi de la
    maison, le mode, et clique sur Installer.

    Peut aussi se lancer directement depuis les sources :
        powershell -STA -ExecutionPolicy Bypass -File .\Assistant-Dodo.ps1

    ATTENTION ENCODAGE : ce fichier contient des accents. Il doit rester en
    UTF-8 AVEC BOM, sinon Windows PowerShell 5.1 l'interprete en ANSI et
    l'interface s'affiche avec des caracteres errones. Test-DodoLogic.ps1
    verifie la presence du BOM.
#>
[CmdletBinding()]
param(
    [string]$SrcCmd,
    # -SelfTest : construit toute l'interface puis sort SANS l'afficher.
    # C'est le seul moyen de prouver, sur une VRAIE machine Windows, que le
    # script se charge et s'execute jusqu'au bout. Une analyse syntaxique ne
    # suffit pas : elle ne voit ni les erreurs d'execution, ni les appels
    # WinForms invalides -- et le lanceur masque la console, donc une erreur
    # au chargement se traduit par "rien ne se passe".
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Charge utile injectee a la construction de l'exe (zip en base64).
$PAYLOAD = 'AAPAYLOADAA'

$SETUP = Join-Path $env:ProgramData 'Dodo-setup'
$ROOT  = Join-Path $env:ProgramData 'Dodo'

# ---------------------------------------------------------------- charte
$C_INK    = [System.Drawing.Color]::FromArgb(2, 12, 24)
$C_ACCENT = [System.Drawing.Color]::FromArgb(8, 145, 178)
$C_SIGNAL = [System.Drawing.Color]::FromArgb(0, 229, 255)
$C_BG     = [System.Drawing.Color]::FromArgb(247, 248, 249)
$C_PANEL  = [System.Drawing.Color]::White
$C_WARN   = [System.Drawing.Color]::FromArgb(180, 83, 9)
$C_ERR    = [System.Drawing.Color]::FromArgb(185, 28, 28)
$C_OK     = [System.Drawing.Color]::FromArgb(6, 95, 70)

function Fail($msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, 'Dodo', 'OK', 'Error') | Out-Null
    exit 1
}

# ------------------------------------------------------- droits administrateur
$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $SelfTest -and -not ([Security.Principal.WindowsPrincipal]$ident).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail("Dodo doit être lancé en tant qu'administrateur.`n`n" +
         "Fermez cette fenêtre, faites un clic droit sur Dodo-Installateur.exe " +
         "puis choisissez « Exécuter en tant qu'administrateur ».")
}

# ------------------------------------------------------------- charge utile
function Expand-Payload {
    if ($PAYLOAD -like 'AAPAYLOAD*') {
        # Execution depuis les sources : les scripts sont a cote.
        $local = $PSScriptRoot
        if (Test-Path (Join-Path $local 'Install-Dodo.ps1')) { return $local }
        Fail("Aucune charge utile embarquée et Install-Dodo.ps1 est introuvable à côté de ce script.")
    }
    if (Test-Path -LiteralPath $SETUP) { Remove-Item -LiteralPath $SETUP -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $SETUP -Force | Out-Null
    $zip = Join-Path $SETUP 'payload.zip'
    [System.IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String($PAYLOAD))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $SETUP)
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    $src = Join-Path $SETUP 'src'
    if (-not (Test-Path (Join-Path $src 'Install-Dodo.ps1'))) { Fail("Charge utile incomplète : Install-Dodo.ps1 manquant.") }
    return $src
}
$SRC = Expand-Payload

# ------------------------------------------------------------- inventaire
function Get-LocalAccounts {
    $exclus = @('DefaultAccount', 'WDAGUtilityAccount', 'Invite', 'Guest', 'defaultuser0')
    try {
        return @(Get-LocalUser -ErrorAction Stop |
                 Where-Object { $_.Enabled -and $exclus -notcontains $_.Name } |
                 Select-Object -ExpandProperty Name | Sort-Object)
    }
    catch {
        return @((& net.exe user) |
                 Where-Object { $_ -match '^\S' -and $_ -notmatch '^(La commande|The command|Comptes|User accounts|-----)' } |
                 ForEach-Object { $_ -split '\s{2,}' } |
                 Where-Object { $_ -and $exclus -notcontains $_ } | Sort-Object -Unique)
    }
}
function Get-Admins {
    try { return @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop |
                   ForEach-Object { ($_.Name -split '\\')[-1] }) }
    catch { return @() }
}
function Get-Ssids {
    $l = New-Object System.Collections.Generic.List[string]
    # SSID courant : le mot-cle "SSID" est identique dans toutes les langues
    foreach ($ln in @(& netsh.exe wlan show interfaces 2>$null)) {
        if ($ln -match '^\s*SSID\s*:\s*(.+?)\s*$') { $v = $Matches[1].Trim(); if ($v -and -not $l.Contains($v)) { $l.Add($v) } }
    }
    # Profils enregistres (libelle localise : on ne se fie qu'a la partie apres ':')
    foreach ($ln in @(& netsh.exe wlan show profiles 2>$null)) {
        if ($ln -match ':\s*(.+?)\s*$' -and $ln -notmatch '^\s*(Interface|Strategie|Policy)') {
            $v = $Matches[1].Trim()
            if ($v -and $v -notmatch '^<' -and -not $l.Contains($v)) { $l.Add($v) }
        }
    }
    return $l.ToArray()
}
# Cartes typiquement utilisees pour partager la connexion d'un telephone :
# elles sont decochees d'office : les autoriser viderait la mesure de son sens.
$PARTAGE = 'Bluetooth|Personal Area|RNDIS|Remote NDIS|Tethering|iPhone|Android'

function Get-Adapters {
    try {
        return @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne 'Disabled' } |
                 Sort-Object Name | ForEach-Object {
                     $partage = ($_.Name -match $PARTAGE -or $_.InterfaceDescription -match $PARTAGE)
                     [pscustomobject]@{
                         Nom     = $_.Name
                         Libelle = '{0}  -  {1}{2}' -f $_.Name, $_.InterfaceDescription, $(if ($partage) { '   [voie de partage]' } else { '' })
                         Partage = $partage
                     }
                 })
    }
    catch { return @() }
}
function Test-HasWifi {
    try { return (@(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' }).Count -gt 0) }
    catch { return $false }
}

function Get-DodoHorairesInitiales {
    <# Horaires et periodes de depart : configuration deja installee, sinon modele livre. #>
    $src = $null
    foreach ($c in @((Join-Path $ROOT 'etc\dodo.config.json'), (Join-Path $SRC 'dodo.config.json'))) {
        if (Test-Path -LiteralPath $c) {
            try { $src = ([System.IO.File]::ReadAllText($c, [System.Text.Encoding]::UTF8) | ConvertFrom-Json); break } catch { }
        }
    }
    $h = [pscustomobject]@{
        SchoolStart = '21:00'; SchoolEnd  = '06:30'
        HolidayStart = '23:00'; HolidayEnd = '06:30'
        OfflineOnly = $false
        Periodes    = (New-Object System.Collections.Generic.List[object])
    }
    if ($null -ne $src) {
        try { if ($src.schedule.school.start)  { $h.SchoolStart  = [string]$src.schedule.school.start }  } catch { }
        try { if ($src.schedule.school.end)    { $h.SchoolEnd    = [string]$src.schedule.school.end }    } catch { }
        try { if ($src.schedule.holiday.start) { $h.HolidayStart = [string]$src.schedule.holiday.start } } catch { }
        try { if ($src.schedule.holiday.end)   { $h.HolidayEnd   = [string]$src.schedule.holiday.end }   } catch { }
        try { $h.OfflineOnly = [bool]$src.calendar.offlineOnly } catch { }
        try {
            foreach ($o in @($src.calendar.overrides)) {
                if (-not $o.start -or -not $o.endExclusive) { continue }
                $h.Periodes.Add([pscustomobject]@{
                    Label = [string]$o.label
                    Debut = [datetime]::ParseExact([string]$o.start, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                    Fin   = [datetime]::ParseExact([string]$o.endExclusive, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-1)
                })
            }
        }
        catch { }
    }
    return $h
}
$script:Horaires = Get-DodoHorairesInitiales

function Get-DodoVoixInitiale {
    <# Reglages de voix et textes deja en place, sinon les valeurs par defaut. #>
    $v = [pscustomobject]@{
        Active     = $true
        VoiceName  = ''
        Debit      = 0
        Volume     = 100
        Repetition = 20
        Affichage  = 25
        Preavis     = "Attention {name}, l'ordinateur va s'éteindre dans {minutes} minutes. Pense à enregistrer ton travail."
        DerniereMin = "Attention {name}, l'ordinateur va s'éteindre dans une minute. Enregistre tout de suite."
        Extinction  = "Il est l'heure de dormir. L'ordinateur s'éteint maintenant. Bonne nuit !"
    }
    $cfgF = Join-Path $ROOT 'etc\dodo.config.json'
    if (Test-Path -LiteralPath $cfgF) {
        try {
            $c = [System.IO.File]::ReadAllText($cfgF, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($c.PSObject.Properties['speech'] -and $c.speech) {
                foreach ($paire in @(@('enabled','Active'), @('voiceName','VoiceName'), @('rate','Debit'),
                                     @('volume','Volume'), @('repeatEverySeconds','Repetition'),
                                     @('displaySeconds','Affichage'))) {
                    if ($c.speech.PSObject.Properties[$paire[0]]) { $v.($paire[1]) = $c.speech.($paire[0]) }
                }
            }
        }
        catch { }
    }
    $msgF = Join-Path $ROOT 'etc\dodo.messages.json'
    if (Test-Path -LiteralPath $msgF) {
        try {
            $m = [System.IO.File]::ReadAllText($msgF, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($paire in @(@('warning','Preavis'), @('warningOne','DerniereMin'), @('shutdownNow','Extinction'))) {
                if ($m.PSObject.Properties[$paire[0]] -and $m.($paire[0])) { $v.($paire[1]) = [string]$m.($paire[0]) }
            }
        }
        catch { }
    }
    return $v
}
$script:Voix = Get-DodoVoixInitiale

function Get-DodoVoixDisponibles {
    <#
        Voix reellement presentes sur ce poste, les DEUX jeux. DodoSpeech.ps1
        est charge dans un processus separe : le charger ici forcerait la
        projection WinRT dans l'assistant, dont l'interface est deja lancee.
    #>
    $script:SpeechModule = Join-Path $SRC 'DodoSpeech.ps1'
    if (-not (Test-Path -LiteralPath $script:SpeechModule)) { return @() }
    try {
        $sortie = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command (
            ". '$($script:SpeechModule)'; Get-DodoAllVoices | ConvertTo-Json -Compress") 2>&1 | Out-String
        $sortie = $sortie.Trim()
        if (-not $sortie) { return @() }
        return @($sortie | ConvertFrom-Json)
    }
    catch { return @() }
}


$accounts = Get-LocalAccounts
$admins   = Get-Admins
$hasWifi  = Test-HasWifi

function Show-DodoVoixDialog {
    <#
        Saisie du texte prononcé et choix de la voix. Renvoie $true si validé.

        Les voix « modernes » de Windows 11 (OneCore) sont celles qu'on trouve
        dans Paramètres > Heure et langue > Voix : ce sont les seules qui
        parlent français. Elles apparaissent ici au même titre que les voix
        classiques, préfixées par leur moteur.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Message parlé et voix'
    $d.ClientSize = New-Object System.Drawing.Size(700, 590)
    $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.BackColor = $C_BG
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    # ---------------------------------------------------------------- voix
    $gv = New-Object System.Windows.Forms.GroupBox
    $gv.Text = 'Voix'
    $gv.SetBounds(16, 12, 668, 150); $gv.BackColor = $C_PANEL
    $gv.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($gv)

    $chkVoix = New-Object System.Windows.Forms.CheckBox
    $chkVoix.Text = 'Annoncer le message à voix haute'
    $chkVoix.SetBounds(16, 24, 300, 22)
    $chkVoix.Checked = [bool]$script:Voix.Active
    $chkVoix.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $gv.Controls.Add($chkVoix)

    $lv = New-Object System.Windows.Forms.Label
    $lv.Text = 'Voix :'; $lv.SetBounds(16, 56, 44, 20)
    $lv.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $gv.Controls.Add($lv)

    $cbVoix = New-Object System.Windows.Forms.ComboBox
    $cbVoix.SetBounds(62, 53, 400, 24); $cbVoix.DropDownStyle = 'DropDownList'
    $cbVoix.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $gv.Controls.Add($cbVoix)

    $btnEcoute = New-Object System.Windows.Forms.Button
    $btnEcoute.Text = 'Écouter'; $btnEcoute.SetBounds(474, 52, 90, 27)
    $btnEcoute.BackColor = $C_ACCENT; $btnEcoute.ForeColor = [System.Drawing.Color]::White
    $btnEcoute.FlatStyle = 'Flat'; $btnEcoute.FlatAppearance.BorderSize = 0
    $gv.Controls.Add($btnEcoute)

    $btnRelire = New-Object System.Windows.Forms.Button
    $btnRelire.Text = 'Rechercher'; $btnRelire.SetBounds(572, 52, 84, 27)
    $gv.Controls.Add($btnRelire)

    $lblVoixEtat = New-Object System.Windows.Forms.Label
    $lblVoixEtat.SetBounds(16, 84, 640, 20)
    $lblVoixEtat.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $gv.Controls.Add($lblVoixEtat)

    $lblAide = New-Object System.Windows.Forms.Label
    $lblAide.SetBounds(16, 106, 640, 36)
    $lblAide.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $lblAide.ForeColor = [System.Drawing.Color]::Gray
    $gv.Controls.Add($lblAide)

    $script:VoixListe = @()
    function Remplir-Voix {
        $cbVoix.Items.Clear()
        [void]$cbVoix.Items.Add('Choix automatique (voix française si présente)')
        $script:VoixListe = @(Get-DodoVoixDisponibles)
        foreach ($v in $script:VoixListe) {
            [void]$cbVoix.Items.Add(('[{0}] {1}  ({2})' -f $v.Engine, $v.Name, $v.Culture))
        }
        $cbVoix.SelectedIndex = 0
        for ($i = 0; $i -lt $script:VoixListe.Count; $i++) {
            if ($script:VoixListe[$i].Name -eq $script:Voix.VoiceName) { $cbVoix.SelectedIndex = $i + 1; break }
        }
        $fr = @($script:VoixListe | Where-Object { $_.IsFrench }).Count
        $oc = @($script:VoixListe | Where-Object { $_.Engine -eq 'OneCore' }).Count
        $lblVoixEtat.Text = ('{0} voix trouvées sur ce PC : {1} modernes (Windows 11), {2} en français.' -f
                             $script:VoixListe.Count, $oc, $fr)
        if ($fr -gt 0) {
            $lblVoixEtat.ForeColor = $C_OK
            $lblAide.Text = "Le « choix automatique » prend la première voix française. Le bouton Écouter fait dire le texte du préavis ci-dessous."
        }
        else {
            $lblVoixEtat.ForeColor = $C_WARN
            $lblAide.Text = ("Aucune voix française sur ce PC. Pour en ajouter : Paramètres > Heure et langue > Voix > " +
                             "Ajouter des voix > Français.`r`nSans cela, le message sera lu avec une voix anglaise.")
        }
    }
    Remplir-Voix
    $btnRelire.Add_Click({ Remplir-Voix })

    # ------------------------------------------------------------- cadence
    $gc = New-Object System.Windows.Forms.GroupBox
    $gc.Text = 'Répétition pendant le décompte'
    $gc.SetBounds(16, 170, 668, 82); $gc.BackColor = $C_PANEL
    $gc.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($gc)

    function Nombre($parent, $x, $y, $min, $max, $val) {
        $n = New-Object System.Windows.Forms.NumericUpDown
        $n.SetBounds($x, $y, 64, 24); $n.Minimum = $min; $n.Maximum = $max
        $n.Value = [math]::Max($min, [math]::Min($max, [int]$val))
        $n.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $parent.Controls.Add($n); return $n
    }
    function Etiq2($parent, $txt, $x, $y, $w) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $txt; $l.SetBounds($x, $y, $w, 20)
        $l.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $parent.Controls.Add($l); return $l
    }

    Etiq2 $gc 'Répéter le message toutes les' 16 28 180 | Out-Null
    $nRep = Nombre $gc 200 24 0 300 $script:Voix.Repetition
    Etiq2 $gc 'secondes  (0 = une seule fois)' 270 28 200 | Out-Null

    Etiq2 $gc 'Fenêtre affichée pendant' 16 54 180 | Out-Null
    $nAff = Nombre $gc 200 50 5 300 $script:Voix.Affichage
    Etiq2 $gc 'secondes' 270 54 80 | Out-Null

    $lblCadence = New-Object System.Windows.Forms.Label
    $lblCadence.SetBounds(370, 40, 286, 32)
    $lblCadence.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $lblCadence.ForeColor = $C_ACCENT
    $gc.Controls.Add($lblCadence)

    function Maj-Cadence {
        $n = 1
        if ([int]$nRep.Value -gt 0) { $n = 1 + [math]::Floor(([int]$nAff.Value - 1) / [int]$nRep.Value) }
        if ($n -lt 1) { $n = 1 }
        $lblCadence.Text = ('Le message sera prononcé {0} fois à chaque alerte.' -f $n)
    }
    Maj-Cadence
    $nRep.Add_ValueChanged({ Maj-Cadence })
    $nAff.Add_ValueChanged({ Maj-Cadence })

    # -------------------------------------------------------------- textes
    $gt = New-Object System.Windows.Forms.GroupBox
    $gt.Text = 'Ce que la voix doit dire'
    $gt.SetBounds(16, 260, 668, 250); $gt.BackColor = $C_PANEL
    $gt.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($gt)

    function Zone($parent, $titre, $y, $val) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $titre; $l.SetBounds(16, $y, 640, 18)
        $l.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $parent.Controls.Add($l)
        $t = New-Object System.Windows.Forms.TextBox
        $t.SetBounds(16, ($y + 20), 636, 42); $t.Multiline = $true
        $t.Text = $val
        $t.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $parent.Controls.Add($t); return $t
    }
    $tPre = Zone $gt 'Préavis (10, 5 et 2 minutes avant)' 24  $script:Voix.Preavis
    $tOne = Zone $gt 'Dernière minute'                    94  $script:Voix.DerniereMin
    $tFin = Zone $gt 'Au moment de l''extinction'         164 $script:Voix.Extinction

    $lblJetons = New-Object System.Windows.Forms.Label
    $lblJetons.Text = '{minutes} est remplacé par le nombre de minutes restantes, {name} par le prénom du compte Windows.'
    $lblJetons.SetBounds(16, 516, 668, 20)
    $lblJetons.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $lblJetons.ForeColor = [System.Drawing.Color]::Gray
    $d.Controls.Add($lblJetons)

    # ------------------------------------------------------------- ecouter
    $btnEcoute.Add_Click({
        $txt = $tPre.Text.Replace('{minutes}', '10').Replace('{name}', $env:USERNAME)
        if (-not $txt.Trim()) {
            [System.Windows.Forms.MessageBox]::Show('Le texte du préavis est vide.', 'Dodo', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $chkVoix.Checked) {
            [System.Windows.Forms.MessageBox]::Show(
                "La voix est désactivée : cochez « Annoncer le message à voix haute » pour l'entendre.",
                'Dodo', 'OK', 'Information') | Out-Null
            return
        }
        $nom = ''
        if ($cbVoix.SelectedIndex -gt 0) { $nom = $script:VoixListe[$cbVoix.SelectedIndex - 1].Name }
        $agent = Join-Path $SRC 'Show-DodoWarning.ps1'
        if (-not (Test-Path -LiteralPath $agent)) {
            [System.Windows.Forms.MessageBox]::Show('Show-DodoWarning.ps1 est introuvable.', 'Dodo', 'OK', 'Error') | Out-Null
            return
        }
        # L'essai passe par le moteur reel, avec les memes reglages que ceux
        # qui seront installes : ce qu'on entend ici est ce qu'on entendra.
        $sp = @{ enabled = $true; engine = 'auto'; voiceName = $nom
                 rate = [int]$script:Voix.Debit; volume = [int]$script:Voix.Volume } | ConvertTo-Json -Compress
        $fichierSp = Join-Path $env:TEMP 'dodo-essai-voix.json'
        [System.IO.File]::WriteAllText($fichierSp, $sp, (New-Object System.Text.UTF8Encoding($false)))
        $btnEcoute.Enabled = $false
        $d.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $script:EssaiVoix = @'
param($Agent, $Texte, $Reglages)
. (Join-Path (Split-Path -Parent $Agent) 'DodoSpeech.ps1')
$sp = [System.IO.File]::ReadAllText($Reglages, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$r = Invoke-DodoSpeak -Text $Texte -Speech $sp
Write-Output $r
Start-Sleep -Seconds ([math]::Min(30, 2 + [int]($Texte.Length / 12)))
'@
            $fichierPs = Join-Path $env:TEMP 'dodo-essai-voix.ps1'
            [System.IO.File]::WriteAllText($fichierPs, $script:EssaiVoix, (New-Object System.Text.UTF8Encoding($true)))
            $res = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fichierPs $agent $txt $fichierSp 2>&1 | Out-String
            $voie = ($res -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
            $lblVoixEtat.Text = ('Essai : {0}' -f $voie)
            $lblVoixEtat.ForeColor = $(if ($voie -like '*aucun*' -or $voie -like '*desactivee*') { $C_ERR } else { $C_OK })
        }
        catch {
            $lblVoixEtat.Text = ('Essai impossible : {0}' -f $_.Exception.Message)
            $lblVoixEtat.ForeColor = $C_ERR
        }
        finally {
            $d.Cursor = [System.Windows.Forms.Cursors]::Default
            $btnEcoute.Enabled = $true
        }
    })

    # -------------------------------------------------------------- valider
    $bOk = New-Object System.Windows.Forms.Button
    $bOk.Text = 'Valider'; $bOk.SetBounds(440, 544, 120, 34)
    $bOk.BackColor = $C_ACCENT; $bOk.ForeColor = [System.Drawing.Color]::White
    $bOk.FlatStyle = 'Flat'; $bOk.FlatAppearance.BorderSize = 0
    $bOk.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($bOk)
    $bCan = New-Object System.Windows.Forms.Button
    $bCan.Text = 'Annuler'; $bCan.SetBounds(570, 544, 114, 34)
    $bCan.DialogResult = 'Cancel'
    $d.Controls.Add($bCan)
    $d.CancelButton = $bCan

    $script:VoixValide = $false
    $bOk.Add_Click({
        foreach ($paire in @(@($tPre, 'préavis'), @($tOne, 'dernière minute'), @($tFin, 'extinction'))) {
            if (-not $paire[0].Text.Trim()) {
                [System.Windows.Forms.MessageBox]::Show(
                    ("Le texte « {0} » est vide.`n`nUn message vide ne serait ni dit ni affiché." -f $paire[1]),
                    'Dodo', 'OK', 'Warning') | Out-Null
                $paire[0].Focus(); return
            }
        }
        $script:Voix.Active     = [bool]$chkVoix.Checked
        $script:Voix.VoiceName  = $(if ($cbVoix.SelectedIndex -gt 0) { $script:VoixListe[$cbVoix.SelectedIndex - 1].Name } else { '' })
        $script:Voix.Repetition = [int]$nRep.Value
        $script:Voix.Affichage  = [int]$nAff.Value
        $script:Voix.Preavis     = $tPre.Text.Trim()
        $script:Voix.DerniereMin = $tOne.Text.Trim()
        $script:Voix.Extinction  = $tFin.Text.Trim()
        $script:VoixValide = $true
        $d.Close()
    })

    [void]$d.ShowDialog()
    $d.Dispose()
    return $script:VoixValide
}

function Show-DodoHorairesDialog {
    <# Saisie manuelle des horaires et des periodes de vacances. Renvoie $true si valide. #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Horaires et vacances'
    $d.ClientSize = New-Object System.Drawing.Size(660, 540)
    $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.BackColor = $C_BG
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $gh = New-Object System.Windows.Forms.GroupBox
    $gh.Text = 'Heures d''extinction et de reveil'
    $gh.SetBounds(16, 12, 628, 104); $gh.BackColor = $C_PANEL
    $gh.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($gh)

    function Champ($parent, $x, $y, $val) {
        $t = New-Object System.Windows.Forms.TextBox
        $t.SetBounds($x, $y, 62, 24); $t.Text = $val
        $t.TextAlign = 'Center'
        $t.Font = New-Object System.Drawing.Font('Consolas', 11)
        $parent.Controls.Add($t); return $t
    }
    function Etiq($parent, $txt, $x, $y, $w) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $txt; $l.SetBounds($x, $y, $w, 20)
        $l.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $parent.Controls.Add($l); return $l
    }

    Etiq $gh 'Période scolaire' 16 30 130       | Out-Null
    Etiq $gh 'extinction à'     150 32 76       | Out-Null
    $tSS = Champ $gh 228 28 $script:Horaires.SchoolStart
    Etiq $gh 'réveil à'         310 32 56       | Out-Null
    $tSE = Champ $gh 372 28 $script:Horaires.SchoolEnd

    Etiq $gh 'Vacances scolaires' 16 66 130     | Out-Null
    Etiq $gh 'extinction à'     150 68 76       | Out-Null
    $tHS = Champ $gh 228 64 $script:Horaires.HolidayStart
    Etiq $gh 'réveil à'         310 68 56       | Out-Null
    $tHE = Champ $gh 372 64 $script:Horaires.HolidayEnd
    Etiq $gh 'Format 24 h, par exemple 21:00' 460 46 160 | Out-Null

    $gp = New-Object System.Windows.Forms.GroupBox
    $gp.Text = 'Périodes de vacances scolaires'
    $gp.SetBounds(16, 124, 628, 340); $gp.BackColor = $C_PANEL
    $gp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($gp)

    $lst = New-Object System.Windows.Forms.ListBox
    $lst.SetBounds(16, 26, 596, 170)
    $lst.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $gp.Controls.Add($lst)

    $travail = New-Object System.Collections.Generic.List[object]
    foreach ($x in $script:Horaires.Periodes) { $travail.Add($x) }

    function Rafraichir {
        $lst.Items.Clear()
        foreach ($x in ($travail | Sort-Object Debut)) {
            [void]$lst.Items.Add(('{0,-34} du {1} au {2} inclus' -f $x.Label, $x.Debut.ToString('dd/MM/yyyy'), $x.Fin.ToString('dd/MM/yyyy')))
        }
    }
    Rafraichir

    Etiq $gp 'Nom' 16 210 40 | Out-Null
    $tLab = New-Object System.Windows.Forms.TextBox
    $tLab.SetBounds(56, 206, 200, 24); $tLab.Text = 'Vacances'
    $gp.Controls.Add($tLab)
    Etiq $gp 'du' 268 210 24 | Out-Null
    $dpD = New-Object System.Windows.Forms.DateTimePicker
    $dpD.SetBounds(294, 206, 130, 24); $dpD.Format = 'Short'
    $gp.Controls.Add($dpD)
    Etiq $gp 'au' 434 210 24 | Out-Null
    $dpF = New-Object System.Windows.Forms.DateTimePicker
    $dpF.SetBounds(458, 206, 130, 24); $dpF.Format = 'Short'
    $gp.Controls.Add($dpF)
    Etiq $gp 'Dates incluses : le dernier jour saisi est le dernier soir « vacances ». La rentrée est le lendemain.' 16 236 596 | Out-Null

    $bAdd = New-Object System.Windows.Forms.Button
    $bAdd.Text = 'Ajouter'; $bAdd.SetBounds(16, 262, 110, 30)
    $bAdd.BackColor = $C_ACCENT; $bAdd.ForeColor = [System.Drawing.Color]::White
    $bAdd.FlatStyle = 'Flat'; $bAdd.FlatAppearance.BorderSize = 0
    $gp.Controls.Add($bAdd)
    $bDel = New-Object System.Windows.Forms.Button
    $bDel.Text = 'Supprimer la ligne'; $bDel.SetBounds(136, 262, 150, 30)
    $gp.Controls.Add($bDel)

    $chkOff = New-Object System.Windows.Forms.CheckBox
    $chkOff.Text = 'Ne pas utiliser Internet — seules les périodes ci-dessus font foi'
    $chkOff.SetBounds(16, 300, 460, 24)
    $chkOff.Checked = [bool]$script:Horaires.OfflineOnly
    $gp.Controls.Add($chkOff)

    $bAdd.Add_Click({
        if ($dpF.Value.Date -lt $dpD.Value.Date) {
            [System.Windows.Forms.MessageBox]::Show('La date de fin précède la date de début.', 'Dodo', 'OK', 'Warning') | Out-Null
            return
        }
        $lab = $tLab.Text.Trim()
        if (-not $lab) { $lab = 'Vacances' }
        $travail.Add([pscustomobject]@{ Label = $lab; Debut = $dpD.Value.Date; Fin = $dpF.Value.Date })
        Rafraichir
    })
    $bDel.Add_Click({
        if ($lst.SelectedIndex -lt 0) { return }
        $tries = @($travail | Sort-Object Debut)
        $cible = $tries[$lst.SelectedIndex]
        [void]$travail.Remove($cible)
        Rafraichir
    })

    $bOk = New-Object System.Windows.Forms.Button
    $bOk.Text = 'Valider'; $bOk.SetBounds(400, 480, 120, 34)
    $bOk.BackColor = $C_ACCENT; $bOk.ForeColor = [System.Drawing.Color]::White
    $bOk.FlatStyle = 'Flat'; $bOk.FlatAppearance.BorderSize = 0
    $bOk.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $d.Controls.Add($bOk)
    $bCan = New-Object System.Windows.Forms.Button
    $bCan.Text = 'Annuler'; $bCan.SetBounds(530, 480, 114, 34)
    $bCan.DialogResult = 'Cancel'
    $d.Controls.Add($bCan)
    $d.CancelButton = $bCan

    $script:HorairesValides = $false
    $bOk.Add_Click({
        $motif = '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        foreach ($c in @($tSS, $tSE, $tHS, $tHE)) {
            if ($c.Text.Trim() -notmatch $motif) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Heure invalide : « $($c.Text) »`n`nFormat attendu : HH:mm sur 24 heures, par exemple 21:00 ou 06:30.",
                    'Dodo', 'OK', 'Warning') | Out-Null
                $c.Focus(); return
            }
        }
        # La fenetre doit passer minuit : l'extinction est posterieure au reveil.
        foreach ($paire in @(@($tSS, $tSE, 'scolaire'), @($tHS, $tHE, 'vacances'))) {
            if ([TimeSpan]::Parse($paire[0].Text.Trim()) -le [TimeSpan]::Parse($paire[1].Text.Trim())) {
                [System.Windows.Forms.MessageBox]::Show(
                    ("Règle {0} : l'heure d'extinction ({1}) doit être postérieure à l'heure de réveil ({2}).`n`n" +
                     "La fenêtre passe minuit : par exemple 21:00 le soir, 06:30 le lendemain.") -f $paire[2], $paire[0].Text, $paire[1].Text,
                    'Dodo', 'OK', 'Warning') | Out-Null
                return
            }
        }
        if ($chkOff.Checked -and $travail.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Sans Internet et sans aucune période saisie, la règle scolaire s'appliquerait toute l'année.`n`n" +
                "Ajoutez au moins une période, ou décochez « Ne pas utiliser Internet ».", 'Dodo', 'OK', 'Warning') | Out-Null
            return
        }
        $script:Horaires.SchoolStart  = $tSS.Text.Trim()
        $script:Horaires.SchoolEnd    = $tSE.Text.Trim()
        $script:Horaires.HolidayStart = $tHS.Text.Trim()
        $script:Horaires.HolidayEnd   = $tHE.Text.Trim()
        $script:Horaires.OfflineOnly  = [bool]$chkOff.Checked
        $script:Horaires.Periodes     = (New-Object System.Collections.Generic.List[object])
        foreach ($x in ($travail | Sort-Object Debut)) { $script:Horaires.Periodes.Add($x) }
        $script:HorairesValides = $true
        $d.Close()
    })

    [void]$d.ShowDialog()
    return $script:HorairesValides
}

# ================================================================= interface
$f = New-Object System.Windows.Forms.Form
$f.Text = 'Dodo - assistant d''installation'
$f.ClientSize = New-Object System.Drawing.Size(780, 810)
$f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedDialog'
$f.MaximizeBox = $false
$f.BackColor = $C_BG
$f.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$head = New-Object System.Windows.Forms.Panel
$head.Dock = 'Top'; $head.Height = 74; $head.BackColor = $C_INK
$f.Controls.Add($head)

$bar = New-Object System.Windows.Forms.Panel
$bar.SetBounds(24, 18, 26, 3); $bar.BackColor = $C_SIGNAL
$head.Controls.Add($bar)

$t1 = New-Object System.Windows.Forms.Label
$t1.Text = 'Dodo'; $t1.ForeColor = [System.Drawing.Color]::White
$t1.Font = New-Object System.Drawing.Font('Segoe UI', 19, [System.Drawing.FontStyle]::Bold)
$t1.SetBounds(22, 24, 110, 34); $head.Controls.Add($t1)

$t2 = New-Object System.Windows.Forms.Label
$t2.Text = "Couvre-feu automatique  ·  extinction 21h00 en période scolaire, 23h00 pendant les vacances zone C"
$t2.ForeColor = [System.Drawing.Color]::FromArgb(201, 212, 222)
$t2.SetBounds(112, 36, 650, 20); $head.Controls.Add($t2)

function New-Group([string]$title, [int]$top, [int]$height) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $title; $g.SetBounds(20, $top, 740, $height)
    $g.BackColor = $C_PANEL; $g.ForeColor = $C_INK
    $g.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $f.Controls.Add($g); return $g
}
function New-Lbl([string]$txt, [int]$x, [int]$y, [int]$w, $parent, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $txt; $l.SetBounds($x, $y, $w, 32); $l.AutoSize = $false
    $l.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    if ($color) { $l.ForeColor = $color }
    $parent.Controls.Add($l); return $l
}

# --- 1. compte de l'enfant
$g1 = New-Group '1.  Compte de l''enfant' 88 96
$cbChild = New-Object System.Windows.Forms.ComboBox
$cbChild.SetBounds(16, 26, 250, 24); $cbChild.DropDownStyle = 'DropDownList'
foreach ($a in $accounts) { [void]$cbChild.Items.Add($a) }
$g1.Controls.Add($cbChild)

$lblAdmin = New-Lbl '' 280 26 300 $g1
$btnDemote = New-Object System.Windows.Forms.Button
$btnDemote.Text = 'Retirer des administrateurs'; $btnDemote.SetBounds(560, 24, 165, 26)
$btnDemote.Visible = $false; $g1.Controls.Add($btnDemote)
New-Lbl "L'enfant doit être un compte standard : un administrateur peut tout désactiver en trois clics." 16 58 700 $g1 ([System.Drawing.Color]::Gray) | Out-Null

# --- 2. adultes exemptes
$g2 = New-Group '2.  Comptes adultes exemptés  (le poste ne s''éteindra pas devant eux)' 190 108
$clAdults = New-Object System.Windows.Forms.CheckedListBox
$clAdults.SetBounds(16, 24, 708, 72); $clAdults.CheckOnClick = $true
$clAdults.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$clAdults.MultiColumn = $true; $clAdults.ColumnWidth = 175
foreach ($a in $accounts) { [void]$clAdults.Items.Add($a) }
$g2.Controls.Add($clAdults)

# --- 3. reseau
$g3 = New-Group '3.  Bloquer le partage de connexion du téléphone' 306 138
$chkNet = New-Object System.Windows.Forms.CheckBox
$chkNet.Text = "Interdire tout réseau autre que le Wi-Fi de la maison"
$chkNet.SetBounds(16, 24, 420, 22); $chkNet.Checked = $true
$chkNet.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$g3.Controls.Add($chkNet)

New-Lbl 'Wi-Fi de la maison :' 16 52 120 $g3 | Out-Null
$cbSsid = New-Object System.Windows.Forms.ComboBox
$cbSsid.SetBounds(140, 49, 300, 24); $cbSsid.DropDownStyle = 'DropDown'
foreach ($s in @(Get-Ssids)) { [void]$cbSsid.Items.Add($s) }
if ($cbSsid.Items.Count -gt 0) { $cbSsid.SelectedIndex = 0 }
$g3.Controls.Add($cbSsid)

$btnSsid = New-Object System.Windows.Forms.Button
$btnSsid.Text = 'Détecter'; $btnSsid.SetBounds(450, 48, 80, 26); $g3.Controls.Add($btnSsid)

$lstAd = New-Object System.Windows.Forms.CheckedListBox
$lstAd.SetBounds(16, 78, 708, 52)
$lstAd.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lstAd.CheckOnClick = $true
$g3.Controls.Add($lstAd)

function Fill-Adapters {
    $lstAd.Items.Clear()
    $script:AdapterRows = @(Get-Adapters)
    foreach ($a in $script:AdapterRows) { [void]$lstAd.Items.Add($a.Libelle, (-not $a.Partage)) }
}
Fill-Adapters

# --- 4. mode
$g4 = New-Group '4.  Horaires, message parlé et mode' 452 152
$rbSim = New-Object System.Windows.Forms.RadioButton
$rbSim.Text = 'Tester d''abord  —  simulation : tout est journalisé, rien ne s''éteint  (recommandé)'
$rbSim.SetBounds(16, 22, 600, 22); $rbSim.Checked = $true; $g4.Controls.Add($rbSim)
$rbProd = New-Object System.Windows.Forms.RadioButton
$rbProd.Text = 'Mise en service  —  le poste s''éteindra réellement aux horaires ci-dessus'
$rbProd.SetBounds(16, 46, 600, 22); $g4.Controls.Add($rbProd)

$lblHoraires = New-Lbl '' 16 74 520 $g4
$lblHoraires.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblHoraires.ForeColor = $C_ACCENT
$btnHoraires = New-Object System.Windows.Forms.Button
$btnHoraires.Text = 'Horaires et vacances...'; $btnHoraires.SetBounds(545, 74, 180, 30)
$g4.Controls.Add($btnHoraires)

$lblVoix = New-Lbl '' 16 110 520 $g4
$lblVoix.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblVoix.ForeColor = $C_ACCENT
$btnVoix = New-Object System.Windows.Forms.Button
$btnVoix.Text = 'Message parlé et voix...'; $btnVoix.SetBounds(545, 110, 180, 30)
$g4.Controls.Add($btnVoix)

# --- boutons
$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = 'Installer'; $btnGo.SetBounds(20, 628, 150, 34)
$btnGo.BackColor = $C_ACCENT; $btnGo.ForeColor = [System.Drawing.Color]::White
$btnGo.FlatStyle = 'Flat'; $btnGo.FlatAppearance.BorderSize = 0
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$f.Controls.Add($btnGo)

function New-Btn([string]$t, [int]$x, [int]$w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t; $b.SetBounds($x, 628, $w, 34); $f.Controls.Add($b); return $b
}
$btnState  = New-Btn 'Voir l''état'        180 120
$btnEve    = New-Btn 'Tester une soirée'   310 150
$btnUnins  = New-Btn 'Désinstaller'        470 120
$btnClose  = New-Btn 'Fermer'              660 100

$log = New-Object System.Windows.Forms.RichTextBox
$log.SetBounds(20, 674, 740, 118); $log.ReadOnly = $true
$log.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$log.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 251)
$f.Controls.Add($log)

# ================================================================= logique
function Log([string]$m, $color = $null) {
    if ($null -eq $color) {
        $color = [System.Drawing.Color]::FromArgb(40, 46, 54)
        if ($m -match '^\s*OK\s')            { $color = $C_OK }
        elseif ($m -match '^\s*!\s' -or $m -match 'WARN|reserve') { $color = $C_WARN }
        elseif ($m -match 'ECHEC|Erreur|refus|Exception') { $color = $C_ERR }
        elseif ($m -match '^\[\d+\]')        { $color = $C_ACCENT }
    }
    $log.SelectionStart = $log.TextLength
    $log.SelectionColor = $color
    $log.AppendText($m + "`r`n")
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-Child {
    $n = [string]$cbChild.SelectedItem
    if (-not $n) { $lblAdmin.Text = ''; $btnDemote.Visible = $false; return }
    if ($admins -contains $n) {
        $lblAdmin.Text = "ATTENTION : ce compte est administrateur."
        $lblAdmin.ForeColor = $C_ERR
        $btnDemote.Visible = $true
    }
    else {
        $lblAdmin.Text = "Compte standard - c'est bien ce qu'il faut."
        $lblAdmin.ForeColor = $C_OK
        $btnDemote.Visible = $false
    }
}
$cbChild.Add_SelectedIndexChanged({ Refresh-Child })

function Update-HorairesLabel {
    $lblHoraires.Text = ('Scolaire {0} - {1}   ·   Vacances {2} - {3}   ·   {4} période(s) saisie(s){5}' -f
        $script:Horaires.SchoolStart, $script:Horaires.SchoolEnd,
        $script:Horaires.HolidayStart, $script:Horaires.HolidayEnd,
        $script:Horaires.Periodes.Count,
        $(if ($script:Horaires.OfflineOnly) { '   ·   sans Internet' } else { '' }))
}
function Update-VoixLabel {
    if (-not $script:Voix.Active) {
        $lblVoix.Text = 'Message parlé : désactivé — seule la fenêtre s''affichera.'
        return
    }
    $n = 1
    if ([int]$script:Voix.Repetition -gt 0) {
        $n = 1 + [math]::Floor(([int]$script:Voix.Affichage - 1) / [int]$script:Voix.Repetition)
    }
    if ($n -lt 1) { $n = 1 }
    $lblVoix.Text = ('Voix : {0}   ·   message répété {1} fois par alerte' -f
        $(if ($script:Voix.VoiceName) { $script:Voix.VoiceName } else { 'choix automatique' }), $n)
}
Update-VoixLabel

$btnVoix.Add_Click({
    if (Show-DodoVoixDialog) {
        Update-VoixLabel
        Log ('OK   Message parlé : {0}, répétition toutes les {1} s, fenêtre {2} s.' -f
            $(if ($script:Voix.Active) { 'activé' } else { 'désactivé' }),
            $script:Voix.Repetition, $script:Voix.Affichage)
        Log ('     Préavis : « {0} »' -f $script:Voix.Preavis)
    }
})

$btnHoraires.Add_Click({
    if (Show-DodoHorairesDialog) {
        Update-HorairesLabel
        Log ('OK   Horaires : scolaire {0}-{1}, vacances {2}-{3} ; {4} période(s) de vacances{5}.' -f
            $script:Horaires.SchoolStart, $script:Horaires.SchoolEnd,
            $script:Horaires.HolidayStart, $script:Horaires.HolidayEnd,
            $script:Horaires.Periodes.Count,
            $(if ($script:Horaires.OfflineOnly) { ', sans Internet' } else { '' }))
    }
})

$btnDemote.Add_Click({
    $n = [string]$cbChild.SelectedItem
    if (-not $n) { return }
    try {
        Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $n -ErrorAction Stop
        Log "OK   '$n' retiré du groupe Administrateurs. Effectif à sa prochaine ouverture de session."
        $script:admins = @(Get-Admins)
        Refresh-Child
    }
    catch { Log "ÉCHEC du retrait de '$n' : $($_.Exception.Message)" $C_ERR }
})

$btnSsid.Add_Click({
    $cbSsid.Items.Clear()
    foreach ($s in @(Get-Ssids)) { [void]$cbSsid.Items.Add($s) }
    if ($cbSsid.Items.Count -gt 0) { $cbSsid.SelectedIndex = 0 }
    Fill-Adapters
    Log "OK   $($cbSsid.Items.Count) réseau(x) et $($lstAd.Items.Count) carte(s) détecté(s)."
})

function Pump([string]$file, [int]$n) {
    $all = @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)
    if ($all.Count -gt $n) { for ($i = $n; $i -lt $all.Count; $i++) { Log $all[$i] } ; return $all.Count }
    return $n
}

function Run-Script {
    param([string]$File, [string]$Arguments = '', [string]$Titre)
    if (-not (Test-Path -LiteralPath $File)) { Log "ÉCHEC : script introuvable — $File" $C_ERR; return 1 }
    Log ''; Log ("===== $Titre " + ('=' * [math]::Max(0, 60 - $Titre.Length))) $C_ACCENT
    foreach ($b in @($btnGo, $btnState, $btnEve, $btnUnins, $btnDemote, $btnSsid)) { $b.Enabled = $false }
    $f.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $o = Join-Path $env:TEMP ('dodo-o-' + [guid]::NewGuid().ToString('N') + '.txt')
    $e = Join-Path $env:TEMP ('dodo-e-' + [guid]::NewGuid().ToString('N') + '.txt')
    $rc = 1
    try {
        $cmdline = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $File
        if ($Arguments) { $cmdline += ' ' + $Arguments }
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $cmdline -NoNewWindow -PassThru `
                           -RedirectStandardOutput $o -RedirectStandardError $e
        $n = 0
        while (-not $p.HasExited) {
            $n = Pump $o $n
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 150
        }
        $null = Pump $o $n
        foreach ($l in @(Get-Content -LiteralPath $e -ErrorAction SilentlyContinue)) { if ($l.Trim()) { Log $l $C_ERR } }
        $rc = $p.ExitCode
    }
    catch { Log "ÉCHEC : $($_.Exception.Message)" $C_ERR }
    finally {
        Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
        foreach ($b in @($btnGo, $btnState, $btnEve, $btnUnins, $btnSsid)) { $b.Enabled = $true }
        Refresh-Child
        $f.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    return $rc
}

$btnGo.Add_Click({
    $child = [string]$cbChild.SelectedItem
    if (-not $child) {
        [System.Windows.Forms.MessageBox]::Show('Choisissez le compte de l''enfant.', 'Dodo', 'OK', 'Warning') | Out-Null
        return
    }
    if ($admins -contains $child) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Le compte '$child' est administrateur : il pourra désactiver Dodo en trois clics.`n`n" +
            "Voulez-vous continuer quand même ?", 'Dodo', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }
    $ssid = $cbSsid.Text.Trim()
    if ($chkNet.Checked -and $hasWifi -and -not $ssid) {
        [System.Windows.Forms.MessageBox]::Show(
            "Indiquez le nom du Wi-Fi de la maison, ou décochez le blocage du partage de connexion.",
            'Dodo', 'OK', 'Warning') | Out-Null
        return
    }
    $cartes = @()
    for ($i = 0; $i -lt $lstAd.Items.Count; $i++) {
        if ($lstAd.GetItemChecked($i)) { $cartes += $script:AdapterRows[$i].Nom }
    }
    if ($chkNet.Checked -and $cartes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Aucune carte réseau n'est cochée : le poste serait coupé de tout réseau.`n`n" +
            "Cochez au moins la carte que l'enfant doit pouvoir utiliser.", 'Dodo', 'OK', 'Warning') | Out-Null
        return
    }

    # Récapitulatif : c'est ici qu'on rattrape un mauvais Wi-Fi (un réseau
    # d'entreprise détecté au lieu de celui de la maison, par exemple).
    $recap = "Compte de l'enfant : $child`n"
    $ex = @($clAdults.CheckedItems | ForEach-Object { [string]$_ })
    $recap += "Adultes exemptés   : " + $(if ($ex.Count) { $ex -join ', ' } else { 'aucun' }) + "`n"
    $recap += ("Scolaire           : extinction {0}, réveil {1}`n" -f $script:Horaires.SchoolStart, $script:Horaires.SchoolEnd)
    $recap += ("Vacances           : extinction {0}, réveil {1}  ({2} période(s) saisie(s))`n" -f $script:Horaires.HolidayStart, $script:Horaires.HolidayEnd, $script:Horaires.Periodes.Count)
    $recap += "Mode               : " + $(if ($rbProd.Checked) { 'MISE EN SERVICE - extinction réelle' } else { 'simulation - rien ne s''éteint' }) + "`n`n"
    if ($chkNet.Checked) {
        if ($hasWifi) { $recap += "Seul Wi-Fi autorisé : $ssid`n" }
        $recap += "Cartes autorisées  : " + ($cartes -join ', ') + "`n"
        $bloquees = @()
        for ($i = 0; $i -lt $lstAd.Items.Count; $i++) { if (-not $lstAd.GetItemChecked($i)) { $bloquees += $script:AdapterRows[$i].Nom } }
        if ($bloquees.Count) { $recap += "Cartes bloquées    : " + ($bloquees -join ', ') + "`n" }
        $recap += "`nVérifiez le nom du Wi-Fi : si ce n'est pas celui de VOTRE maison, "
        $recap += "le portable ne pourra plus se connecter chez vous.`n"
        $recap += "Le téléphone est-il bien DÉBRANCHÉ de ce PC ?"
    }
    else { $recap += "Blocage du partage de connexion : désactivé." }

    $recap += "`n`nMessage parlé   : "
    if ($script:Voix.Active) {
        $recap += ("{0}`n" -f $(if ($script:Voix.VoiceName) { $script:Voix.VoiceName } else { 'choix automatique' }))
        $recap += ("Texte           : « {0} »" -f $script:Voix.Preavis)
    }
    else { $recap += "désactivé" }

    if ([System.Windows.Forms.MessageBox]::Show($recap + "`n`nInstaller avec ces réglages ?", 'Dodo - vérification',
        'YesNo', 'Question') -ne 'Yes') { return }

    # Les reglages passent par un fichier, jamais par la ligne de commande :
    # powershell.exe -File ne reinterprete pas les quotes PowerShell, et un
    # nom de carte comme « Ethernet 2 » y serait decoupe en deux arguments.
    $ans = [pscustomobject]@{
        Production         = [bool]$rbProd.Checked
        NotifyUser         = $child
        ExemptUsers        = @($clAdults.CheckedItems | ForEach-Object { [string]$_ })
        EnableAdapterGuard = [bool]$chkNet.Checked
        AllowedSsid        = @()
        AllowedAdapterName = @()
        OfflineOnly        = [bool]$script:Horaires.OfflineOnly
        Schedule           = [pscustomobject]@{
            school  = [pscustomobject]@{ start = $script:Horaires.SchoolStart;  end = $script:Horaires.SchoolEnd }
            holiday = [pscustomobject]@{ start = $script:Horaires.HolidayStart; end = $script:Horaires.HolidayEnd }
        }
        Speech             = [pscustomobject]@{
            enabled            = [bool]$script:Voix.Active
            engine             = 'auto'
            voiceName          = [string]$script:Voix.VoiceName
            rate               = [int]$script:Voix.Debit
            volume             = [int]$script:Voix.Volume
            repeatEverySeconds = [int]$script:Voix.Repetition
            displaySeconds     = [int]$script:Voix.Affichage
        }
        Messages           = [pscustomobject]@{
            warning     = [string]$script:Voix.Preavis
            warningOne  = [string]$script:Voix.DerniereMin
            shutdownNow = [string]$script:Voix.Extinction
        }
        Holidays           = @($script:Horaires.Periodes | ForEach-Object {
            [pscustomobject]@{
                label        = $_.Label
                start        = $_.Debut.ToString('yyyy-MM-dd')
                endExclusive = $_.Fin.AddDays(1).ToString('yyyy-MM-dd')
            } })
    }
    if ($chkNet.Checked) {
        if ($hasWifi -and $ssid) { $ans.AllowedSsid = @($ssid) }
        $ans.AllowedAdapterName = @($cartes)
    }
    $ansFile = Join-Path $SETUP 'reponses.json'
    [System.IO.File]::WriteAllText($ansFile, ($ans | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

    $rc = Run-Script -File (Join-Path $SRC 'Install-Dodo.ps1') -Arguments ('-AnswerFile "{0}"' -f $ansFile) -Titre 'INSTALLATION'
    if ($rc -eq 0) {
        Log ''
        if ($rbProd.Checked) { Log "OK   Dodo est en service. Le poste s'éteindra aux horaires prévus." $C_OK }
        else { Log "OK   Dodo est installé en SIMULATION : rien ne s'éteint. Utilisez « Tester une soirée », puis relancez en mode Mise en service." $C_OK }
    }
    else { Log "L'installation s'est terminée avec le code $rc — voir les lignes ci-dessus." $C_ERR }
})

$btnState.Add_Click({
    $null = Run-Script -File (Join-Path $ROOT 'bin\Get-DodoStatus.ps1') -Arguments '-Nights 14' -Titre 'ETAT'
})

$btnEve.Add_Click({
    $t = Join-Path $SETUP 'tests\Test-DodoE2E.ps1'
    if (-not (Test-Path -LiteralPath $t)) { $t = Join-Path (Split-Path -Parent $SRC) 'tests\Test-DodoE2E.ps1' }
    [System.Windows.Forms.MessageBox]::Show(
        "Une soirée entière va être rejouée en une minute : vous allez entendre quatre messages " +
        "et voir quatre fenêtres apparaître.`n`nRien ne s'éteindra (mode simulation requis).",
        'Dodo', 'OK', 'Information') | Out-Null
    $null = Run-Script -File $t -Arguments '-Phase preflight,calendar,security,evening' -Titre 'RECETTE'
})

$btnUnins.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Retirer complètement Dodo de ce PC ?`n`nLes tâches, les filtres Wi-Fi et le dossier " +
        "d'installation seront supprimés, et les cartes réseau désactivées seront réactivées.",
        'Dodo', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    $u = Join-Path $ROOT 'bin\Uninstall-Dodo.ps1'
    if (-not (Test-Path -LiteralPath $u)) { $u = Join-Path $SRC 'Uninstall-Dodo.ps1' }
    $null = Run-Script -File $u -Titre 'DESINSTALLATION'
})

$btnClose.Add_Click({ $f.Close() })

$f.Add_FormClosed({
    if ($PAYLOAD -notlike 'AAPAYLOAD*') {
        Remove-Item -LiteralPath $SETUP -Recurse -Force -ErrorAction SilentlyContinue
    }
})

# preselection : premier compte non administrateur
$pre = @($accounts | Where-Object { $admins -notcontains $_ }) | Select-Object -First 1
if ($pre) { $cbChild.SelectedItem = $pre } elseif ($cbChild.Items.Count -gt 0) { $cbChild.SelectedIndex = 0 }
for ($i = 0; $i -lt $clAdults.Items.Count; $i++) {
    if ($admins -contains [string]$clAdults.Items[$i]) { $clAdults.SetItemChecked($i, $true) }
}
Refresh-Child
Update-HorairesLabel
Log "Poste $env:COMPUTERNAME  -  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Log "OK   Session administrateur : $($ident.Name)"
Log "     $($accounts.Count) compte(s) local(aux), $($admins.Count) administrateur(s), Wi-Fi : $(if($hasWifi){'présent'}else{'absent (poste fixe)'})"
Log "     Vérifiez les quatre sections ci-dessus, puis cliquez sur Installer."

if ($SelfTest) {
    Write-Host ''
    Write-Host 'AUTO-TEST : interface construite sans erreur.' -ForegroundColor Green
    Write-Host ("  sections        : {0} groupes" -f @($f.Controls | Where-Object { $_ -is [System.Windows.Forms.GroupBox] }).Count)
    Write-Host ("  horaires        : {0}" -f $lblHoraires.Text)
    Write-Host ("  message parle   : {0}" -f $lblVoix.Text)
    Write-Host ("  comptes listes  : {0}" -f $cbChild.Items.Count)
    $f.Dispose()
    exit 0
}

[void]$f.ShowDialog()
