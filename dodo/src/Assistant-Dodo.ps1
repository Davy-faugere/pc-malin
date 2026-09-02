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
param([string]$SrcCmd)

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
if (-not ([Security.Principal.WindowsPrincipal]$ident).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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
    return ,$l.ToArray()
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

$accounts = Get-LocalAccounts
$admins   = Get-Admins
$hasWifi  = Test-HasWifi

# ================================================================= interface
$f = New-Object System.Windows.Forms.Form
$f.Text = 'Dodo - assistant d''installation'
$f.ClientSize = New-Object System.Drawing.Size(780, 720)
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
foreach ($s in (Get-Ssids)) { [void]$cbSsid.Items.Add($s) }
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
$g4 = New-Group '4.  Mode' 452 76
$rbSim = New-Object System.Windows.Forms.RadioButton
$rbSim.Text = 'Tester d''abord  —  simulation : tout est journalisé, rien ne s''éteint  (recommandé)'
$rbSim.SetBounds(16, 22, 600, 22); $rbSim.Checked = $true; $g4.Controls.Add($rbSim)
$rbProd = New-Object System.Windows.Forms.RadioButton
$rbProd.Text = 'Mise en service  —  le poste s''éteindra réellement aux horaires ci-dessus'
$rbProd.SetBounds(16, 46, 600, 22); $g4.Controls.Add($rbProd)

# --- boutons
$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = 'Installer'; $btnGo.SetBounds(20, 540, 150, 34)
$btnGo.BackColor = $C_ACCENT; $btnGo.ForeColor = [System.Drawing.Color]::White
$btnGo.FlatStyle = 'Flat'; $btnGo.FlatAppearance.BorderSize = 0
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$f.Controls.Add($btnGo)

function New-Btn([string]$t, [int]$x, [int]$w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t; $b.SetBounds($x, 540, $w, 34); $f.Controls.Add($b); return $b
}
$btnState  = New-Btn 'Voir l''état'        180 120
$btnEve    = New-Btn 'Tester une soirée'   310 150
$btnUnins  = New-Btn 'Désinstaller'        470 120
$btnClose  = New-Btn 'Fermer'              660 100

$log = New-Object System.Windows.Forms.RichTextBox
$log.SetBounds(20, 584, 740, 118); $log.ReadOnly = $true
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
    foreach ($s in (Get-Ssids)) { [void]$cbSsid.Items.Add($s) }
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

    if ([System.Windows.Forms.MessageBox]::Show($recap + "`n`nInstaller avec ces réglages ?", 'Dodo - vérification',
        'YesNo', 'Question') -ne 'Yes') { return }

    $a = @()
    if ($rbProd.Checked) { $a += '-Production' }
    $exempt = @($clAdults.CheckedItems | ForEach-Object { "'" + ([string]$_).Replace("'", "''") + "'" })
    if ($exempt.Count -gt 0) { $a += '-ExemptUsers ' + ($exempt -join ',') }
    $a += "-NotifyUser '" + $child.Replace("'", "''") + "'"
    if ($chkNet.Checked) {
        if ($hasWifi -and $ssid) { $a += "-AllowedSsid '" + $ssid.Replace("'", "''") + "'" }
        $a += '-EnableAdapterGuard'
        $a += '-AllowedAdapterName ' + (($cartes | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ',')
    }

    $rc = Run-Script -File (Join-Path $SRC 'Install-Dodo.ps1') -Arguments ($a -join ' ') -Titre 'INSTALLATION'
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
Log "Poste $env:COMPUTERNAME  -  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Log "OK   Session administrateur : $($ident.Name)"
Log "     $($accounts.Count) compte(s) local(aux), $($admins.Count) administrateur(s), Wi-Fi : $(if($hasWifi){'présent'}else{'absent (poste fixe)'})"
Log "     Vérifiez les quatre sections ci-dessus, puis cliquez sur Installer."

[void]$f.ShowDialog()
