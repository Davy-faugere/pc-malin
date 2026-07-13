param([string]$SrcCmd)

# ── Icone embarquee (balai + eclats) ─────────────────────────────
$IcoB64 = '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'
function Write-Ico { param($icoDir)
    $path = Join-Path $icoDir 'pcmalin.ico'
    try { [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($IcoB64)) } catch {}
    if (Test-Path $path) { return $path } else { return $null }
}

# ── Intercepteur d'erreurs ───────────────────────────────────────
trap {
    try {
        Add-Type -AssemblyName System.Windows.Forms 2>$null
        [System.Windows.Forms.MessageBox]::Show(
            "Un souci est survenu au demarrage :`n`n$($_.Exception.Message)",
            "PC Malin", 'OK', 'Error') | Out-Null
    } catch { Write-Host "ERREUR : $($_.Exception.Message)"; Read-Host "Entree" }
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Emplacement (simple, non cache) ──────────────────────────────
$SrcDir     = Split-Path -Parent $SrcCmd
$InstallDir = Join-Path $env:ProgramData 'PC Malin'
$SrcExt = [IO.Path]::GetExtension($SrcCmd)
$InstallCmd = Join-Path $InstallDir "PC-Malin$SrcExt"
$runFromInstall = $false
try { $runFromInstall = ((Resolve-Path $SrcCmd).Path -eq (Resolve-Path $InstallCmd -EA SilentlyContinue).Path) } catch {}
$AppDir = if ($runFromInstall) { $InstallDir } else { $SrcDir }
$Log = Join-Path $AppDir 'pcmalin.log'
$IcoPath = Write-Ico $AppDir

function Write-Log { param([string]$M)
    try { Add-Content $Log ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $env:USERNAME | $M") -EA SilentlyContinue } catch {}
}

# ── Droits administrateur ────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($SrcExt -eq '.exe') { Start-Process $SrcCmd -Verb RunAs }
    else { Start-Process cmd -Verb RunAs -ArgumentList "/c `"$SrcCmd`"" }
    exit
}

# ── Choix : installer ou juste utiliser ──────────────────────────
if (-not $runFromInstall) {
    $btn = [System.Windows.Forms.MessageBox]::Show(
        "Bienvenue dans PC Malin !`n`n" +
        "Comment souhaitez-vous l'utiliser ?`n`n" +
        "OUI  = L'installer sur cet ordinateur (raccourci sur le Bureau)`n" +
        "NON  = Juste l'utiliser maintenant, sans rien installer`n" +
        "ANNULER = Fermer",
        "PC Malin", 'YesNoCancel', 'Question')
    if ($btn -eq 'Cancel') { exit }
    if ($btn -eq 'Yes') {
        try {
            $null = New-Item $InstallDir -ItemType Directory -Force -EA SilentlyContinue
            Copy-Item $SrcCmd $InstallCmd -Force
            $instIco = Write-Ico $InstallDir
            $wsh = New-Object -ComObject WScript.Shell
            $sc  = $wsh.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\PC Malin.lnk")
            if ($SrcExt -eq '.exe') {
                $sc.TargetPath = $InstallCmd
                $sc.IconLocation = "$InstallCmd,0"
            } else {
                $sc.TargetPath = "$env:SystemRoot\System32\cmd.exe"
                $sc.Arguments  = "/c `"$InstallCmd`""
                if ($instIco) { $sc.IconLocation = "$instIco,0" }
            }
            $sc.WorkingDirectory = $InstallDir
            $sc.Description = "PC Malin - entretien de votre ordinateur"
            $sc.Save()
            Write-Log "INSTALLATION"
            [System.Windows.Forms.MessageBox]::Show(
                "C'est installe !`n`nUn raccourci 'PC Malin' est sur votre Bureau.`n`nOn ouvre l'application...",
                "PC Malin", 'OK', 'Information') | Out-Null
            if ($SrcExt -eq '.exe') { Start-Process $InstallCmd }
            else { Start-Process cmd -ArgumentList "/c `"$InstallCmd`"" }
            exit
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Installation impossible, on continue sans installer.","PC Malin",'OK','Warning') | Out-Null
        }
    }
    Write-Log "DEMARRAGE"
}

# ════════════════════════════════════════════════════════════════
#  THEME CLAIR + HELPERS
# ════════════════════════════════════════════════════════════════
$BgCol    = [Drawing.Color]::FromArgb(244, 246, 249)
$CardBg  = [Drawing.Color]::White
$HdrCol   = [Drawing.Color]::FromArgb(31, 168, 180)   # turquoise accueillant
$Blue  = [Drawing.Color]::FromArgb(45, 140, 220)
$TxtD  = [Drawing.Color]::FromArgb(42, 46, 54)
$Mute  = [Drawing.Color]::FromArgb(107, 114, 128)
$Line  = [Drawing.Color]::FromArgb(226, 232, 240)
$Green = [Drawing.Color]::FromArgb(34, 160, 107)
$Orange= [Drawing.Color]::FromArgb(224, 138, 30)
$Red   = [Drawing.Color]::FromArgb(209, 69, 69)
$Purple= [Drawing.Color]::FromArgb(123, 94, 200)
$Teal  = [Drawing.Color]::FromArgb(31, 168, 180)
$White = [Drawing.Color]::White

$FN  = [Drawing.Font]::new("Segoe UI", 10)
$FNB = [Drawing.Font]::new("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$FNH = [Drawing.Font]::new("Segoe UI", 13, [Drawing.FontStyle]::Bold)

function New-Label { param($txt,$x,$y,$w=200,$h=26,$bold=$false)
    $c = [System.Windows.Forms.Label]::new()
    $c.Text=$txt; $c.Location=[Drawing.Point]::new($x,$y); $c.Size=[Drawing.Size]::new($w,$h)
    $c.TextAlign='MiddleLeft'; $c.Font= if ($bold){$FNB}else{$FN}; $c.ForeColor=$TxtD; $c.BackColor='Transparent'
    return $c
}
function New-Btn { param($txt,$x,$y,$w=200,$h=40,$bg="",$fg="")
    $c = [System.Windows.Forms.Button]::new()
    $c.Text=$txt; $c.Location=[Drawing.Point]::new($x,$y); $c.Size=[Drawing.Size]::new($w,$h)
    $c.BackColor= if ($bg){$bg}else{$Blue}; $c.ForeColor= if ($fg){$fg}else{$White}
    $c.FlatStyle='Flat'; $c.FlatAppearance.BorderSize=0; $c.Font=$FNB; $c.Cursor='Hand'; $c.TextAlign='MiddleCenter'
    return $c
}
function New-Card { param($x,$y,$w,$h)
    $c=[System.Windows.Forms.Panel]::new()
    $c.Location=[Drawing.Point]::new($x,$y); $c.Size=[Drawing.Size]::new($w,$h); $c.BackColor=$CardBg
    return $c
}
function New-Tab { param($name)
    $t=[System.Windows.Forms.TabPage]::new(); $t.Text="   $name   "; $t.BackColor=$BgCol
    $t.Padding=[Windows.Forms.Padding]::new(18,16,18,16); return $t
}
function Dlg-OK { param($m,$t="PC Malin") [System.Windows.Forms.MessageBox]::Show($m,$t,'OK','Information')|Out-Null }
function Dlg-YN { param($m,$t="PC Malin") return ([System.Windows.Forms.MessageBox]::Show($m,$t,'YesNo','Question') -eq 'Yes') }

# ── Icones dessinees ─────────────────────────────────────────────
function Draw-Icon { param($g,[string]$type,$color,$x,$y,$sz)
    $pen=[System.Drawing.Pen]::new($color,2.6); $pen.StartCap='Round'; $pen.EndCap='Round'; $pen.LineJoin='Round'
    $br=[System.Drawing.SolidBrush]::new($color); $g.SmoothingMode='AntiAlias'
    switch ($type) {
        'pc' {
            $g.DrawRectangle($pen,$x,$y,$sz,$sz*0.64)
            $g.DrawLine($pen,$x+$sz*0.33,$y+$sz*0.64,$x+$sz*0.28,$y+$sz*0.82)
            $g.DrawLine($pen,$x+$sz*0.67,$y+$sz*0.64,$x+$sz*0.72,$y+$sz*0.82)
            $g.DrawLine($pen,$x+$sz*0.20,$y+$sz*0.82,$x+$sz*0.80,$y+$sz*0.82)
        }
        'broom' {
            $g.DrawLine($pen,$x+$sz*0.72,$y+$sz*0.08,$x+$sz*0.40,$y+$sz*0.55)
            $g.DrawLine($pen,$x+$sz*0.24,$y+$sz*0.55,$x+$sz*0.60,$y+$sz*0.55)
            $g.DrawLine($pen,$x+$sz*0.26,$y+$sz*0.60,$x+$sz*0.20,$y+$sz*0.92)
            $g.DrawLine($pen,$x+$sz*0.40,$y+$sz*0.60,$x+$sz*0.40,$y+$sz*0.92)
            $g.DrawLine($pen,$x+$sz*0.54,$y+$sz*0.60,$x+$sz*0.60,$y+$sz*0.92)
        }
        'health' {
            $g.DrawLine($pen,$x,$y+$sz*0.5,$x+$sz*0.22,$y+$sz*0.5)
            $g.DrawLine($pen,$x+$sz*0.22,$y+$sz*0.5,$x+$sz*0.34,$y+$sz*0.24)
            $g.DrawLine($pen,$x+$sz*0.34,$y+$sz*0.24,$x+$sz*0.48,$y+$sz*0.76)
            $g.DrawLine($pen,$x+$sz*0.48,$y+$sz*0.76,$x+$sz*0.60,$y+$sz*0.5)
            $g.DrawLine($pen,$x+$sz*0.60,$y+$sz*0.5,$x+$sz,$y+$sz*0.5)
        }
        'bulb' {
            $g.DrawEllipse($pen,$x+$sz*0.24,$y+$sz*0.06,$sz*0.52,$sz*0.52)
            $g.DrawLine($pen,$x+$sz*0.40,$y+$sz*0.62,$x+$sz*0.60,$y+$sz*0.62)
            $g.DrawLine($pen,$x+$sz*0.42,$y+$sz*0.72,$x+$sz*0.58,$y+$sz*0.72)
            $g.DrawLine($pen,$x+$sz*0.45,$y+$sz*0.82,$x+$sz*0.55,$y+$sz*0.82)
        }
    }
    $pen.Dispose(); $br.Dispose()
}

# ════════════════════════════════════════════════════════════════
#  FENETRE PRINCIPALE
# ════════════════════════════════════════════════════════════════
$F = [System.Windows.Forms.Form]::new()
$F.Text = "PC Malin  -  l'entretien facile de votre ordinateur"
$F.ClientSize = [Drawing.Size]::new(900, 644)
$F.StartPosition = 'CenterScreen'
$F.BackColor = $BgCol; $F.Font = $FN
$F.FormBorderStyle = 'FixedSingle'; $F.MaximizeBox = $false
if ($IcoPath -and (Test-Path $IcoPath)) { try { $F.Icon=[System.Drawing.Icon]::new($IcoPath) } catch {} }

# En-tete colore
$hdr = [System.Windows.Forms.Panel]::new()
$hdr.Dock='Top'; $hdr.Height=64; $hdr.BackColor=$HdrCol
$F.Controls.Add($hdr)
$hL = New-Label "  PC Malin" 14 0 170 64 $true
$hL.ForeColor=$White; $hL.Font=[Drawing.Font]::new("Segoe UI",17,[Drawing.FontStyle]::Bold); $hdr.Controls.Add($hL)
$hSub = New-Label "L'entretien facile de votre ordinateur" 196 0 420 64
$hSub.ForeColor=[Drawing.Color]::FromArgb(215,245,248); $hdr.Controls.Add($hSub)
$btnHome = New-Btn "Accueil" 782 16 100 32 ([Drawing.Color]::FromArgb(24,140,150))
$hdr.Controls.Add($btnHome)

# Onglets
$TC = [System.Windows.Forms.TabControl]::new()
$TC.Location=[Drawing.Point]::new(0,64); $TC.Size=[Drawing.Size]::new(900,580); $TC.Font=$FN
$TC.DrawMode='OwnerDrawFixed'; $TC.SizeMode='Fixed'; $TC.ItemSize=[Drawing.Size]::new(222,34)
$TC.Add_DrawItem({
    param($sender,$e)
    $page=$sender.TabPages[$e.Index]; $rect=$sender.GetTabRect($e.Index)
    $selected=($e.Index -eq $sender.SelectedIndex)
    $bg= if ($selected){[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(45,140,220))}else{[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(225,231,240))}
    $e.Graphics.FillRectangle($bg,$rect)
    $fg= if ($selected){[Drawing.Color]::White}else{[Drawing.Color]::FromArgb(80,90,105)}
    $sf=[Drawing.StringFormat]::new(); $sf.Alignment='Center'; $sf.LineAlignment='Center'
    $e.Graphics.DrawString($page.Text.Trim(),[Drawing.Font]::new("Segoe UI",10,[Drawing.FontStyle]::Bold),
        [Drawing.SolidBrush]::new($fg),[Drawing.RectangleF]::new($rect.X,$rect.Y,$rect.Width,$rect.Height),$sf)
    $bg.Dispose()
})
$F.Controls.Add($TC)

# ════════════════════════════════════════════════════════════════
#  ONGLET 1 : MON ORDINATEUR
# ════════════════════════════════════════════════════════════════
$t1 = New-Tab "Mon ordinateur"; $TC.TabPages.Add($t1)
$t1.Controls.Add((New-Label "Voici votre ordinateur en un coup d'oeil" 0 4 600 28 $true))

$cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
$os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
$ramGo = [math]::Round($cs.TotalPhysicalMemory/1GB,0)
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA SilentlyContinue
$upSpan = (Get-Date) - $os.LastBootUpTime
$upTxt = if ($upSpan.Days -ge 1) { "$($upSpan.Days) jour(s) et $($upSpan.Hours) h" } else { "$($upSpan.Hours) h $($upSpan.Minutes) min" }

$infos = @(
    @("Nom de l'ordinateur", $env:COMPUTERNAME),
    @("Marque et modele", "$($cs.Manufacturer)  $($cs.Model)"),
    @("Version de Windows", "$($os.Caption)"),
    @("Memoire vive (RAM)", "$ramGo Go"),
    @("Allume depuis", $upTxt)
)
$yy = 50
foreach ($it in $infos) {
    $cardI = New-Card 0 $yy 800 52; $t1.Controls.Add($cardI)
    $lk = New-Label $it[0] 18 0 260 52; $lk.ForeColor=$Mute; $cardI.Controls.Add($lk)
    $lv = New-Label $it[1] 290 0 495 52 $true; $cardI.Controls.Add($lv)
    $yy += 60
}
# Espace disque avec jauge
$cardD = New-Card 0 $yy 800 78; $t1.Controls.Add($cardD)
$cardD.Controls.Add((New-Label "Espace de stockage (disque C:)" 18 10 400 24 $true))
$pb1 = [System.Windows.Forms.ProgressBar]::new()
$pb1.Location=[Drawing.Point]::new(18,44); $pb1.Size=[Drawing.Size]::new(460,20); $pb1.Style='Continuous'
$cardD.Controls.Add($pb1)
$lblD1 = New-Label "" 492 38 295 30; $cardD.Controls.Add($lblD1)
if ($disk) {
    $usedP=[int]((($disk.Size-$disk.FreeSpace)/$disk.Size)*100)
    $pb1.Value=[math]::Min(100,$usedP)
    $lblD1.Text="{0:N0} Go libres sur {1:N0} Go" -f ($disk.FreeSpace/1GB),($disk.Size/1GB)
    $lblD1.ForeColor= if ($usedP -ge 90){$Red}elseif($usedP -ge 78){$Orange}else{$Green}
}

# ════════════════════════════════════════════════════════════════
#  ONGLET 2 : FAIRE LE MENAGE
# ════════════════════════════════════════════════════════════════
$t2 = New-Tab "Faire le menage"; $TC.TabPages.Add($t2)
$t2.Controls.Add((New-Label "Liberez de l'espace et redonnez du peps a votre PC" 0 4 700 28 $true))

# Bandeau rassurant
$reassure = New-Card 0 42 800 44; $reassure.BackColor=[Drawing.Color]::FromArgb(232,246,240); $t2.Controls.Add($reassure)
$rlbl = New-Label "  Rassurez-vous : vos documents, photos et fichiers personnels ne sont JAMAIS touches." 8 0 786 44
$rlbl.ForeColor=[Drawing.Color]::FromArgb(22,110,75); $reassure.Controls.Add($rlbl)

# Jauge disque
$t2.Controls.Add((New-Label "Espace du disque C:" 0 100 300 24 $true))
$pb2 = [System.Windows.Forms.ProgressBar]::new()
$pb2.Location=[Drawing.Point]::new(0,128); $pb2.Size=[Drawing.Size]::new(500,22); $pb2.Style='Continuous'
$t2.Controls.Add($pb2)
$lblD2 = New-Label "" 516 124 284 30; $t2.Controls.Add($lblD2)
$Script:totalFreed = 0

function Refresh-Disk2 {
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA SilentlyContinue
    if ($d) {
        $up=[int]((($d.Size-$d.FreeSpace)/$d.Size)*100)
        $pb2.Value=[math]::Min(100,$up)
        $lblD2.Text="{0:N0} Go libres sur {1:N0} Go" -f ($d.FreeSpace/1GB),($d.Size/1GB)
        $lblD2.ForeColor= if ($up -ge 90){$Red}elseif($up -ge 78){$Orange}else{$Green}
    }
}
Refresh-Disk2

# Boutons de nettoyage
$cleanBtns = @(
    @("Voir ce qui prend de la place", "analyze", $Blue),
    @("Vider les fichiers temporaires", "temp", $Blue),
    @("Vider la corbeille", "recycle", $Blue),
    @("Nettoyer les fichiers de mise a jour", "wu", $Blue),
    @("Grand nettoyage (tout d'un coup)", "all", $Green)
)
$yb = 168
foreach ($cb in $cleanBtns) {
    $b = New-Btn $cb[0] 0 $yb 340 42 $cb[2]
    $b.Tag=$cb[1]; $b.TextAlign='MiddleLeft'
    $b.Add_Click({ param($sender,$e)
        $rtC.Clear(); $rtC.AppendText("$($sender.Text)`r`n`r`n"); Run-Clean $sender.Tag; Refresh-Disk2
    })
    $t2.Controls.Add($b); $yb += 52
}

# Zone message
$rtC = [System.Windows.Forms.RichTextBox]::new()
$rtC.Location=[Drawing.Point]::new(360,168); $rtC.Size=[Drawing.Size]::new(440,290)
$rtC.Font=[Drawing.Font]::new("Segoe UI",10); $rtC.ReadOnly=$true
$rtC.BackColor=$White; $rtC.ForeColor=$TxtD; $rtC.BorderStyle='FixedSingle'
$t2.Controls.Add($rtC)
$rtC.Text="Choisissez une action a gauche.`r`n`r`nConseil : commencez par 'Voir ce qui prend de la place' pour reperer les gros postes, puis lancez le 'Grand nettoyage'."

function CW { param($t,$col='n')
    $c = switch($col){ 'ok'{$Green} 'hi'{$Blue} 'warn'{$Orange} default{$TxtD} }
    $rtC.SelectionColor=$c; $rtC.AppendText("$t`r`n"); $rtC.ScrollToCaret()
}
function Get-FolderMB { param($p)
    try { return [math]::Round((Get-ChildItem $p -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,0) } catch { return 0 }
}
function Clean-Path { param($p,$label)
    if (-not (Test-Path $p)) { return 0 }
    $before = Get-FolderMB $p
    Get-ChildItem $p -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue } catch {} }
    $gain=[math]::Max(0,$before-(Get-FolderMB $p))
    CW ("  $label : $gain Mo liberes") 'ok'
    return $gain
}
function Run-Clean { param([string]$mode)
    switch ($mode) {
        'analyze' {
            CW "On regarde ce qui occupe de la place..." 'hi'; CW ""
            $paths=@(
                @("$env:TEMP","Fichiers temporaires"),
                @("$env:SystemRoot\Temp","Fichiers temporaires Windows"),
                @("$env:SystemRoot\SoftwareDistribution\Download","Fichiers de mise a jour"),
                @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache","Cache Internet"),
                @("$env:SystemRoot\Logs","Journaux Windows")
            )
            $tot=0
            foreach ($p in $paths) { $sz=Get-FolderMB $p[0]; $tot+=$sz; CW ("  {0,-32} : {1,7} Mo" -f $p[1],$sz) }
            CW ""; CW ("  A recuperer environ : $([math]::Round($tot,0)) Mo") 'hi'
            CW ""; CW "Lancez 'Grand nettoyage' pour tout nettoyer d'un coup." 'warn'
        }
        'temp' {
            $g=0; $g+=Clean-Path "$env:TEMP" "Fichiers temporaires"; $g+=Clean-Path "$env:SystemRoot\Temp" "Temporaires Windows"
            $Script:totalFreed+=$g; CW ""; CW ("C'est fait : $([math]::Round($g,0)) Mo liberes.") 'hi'
        }
        'recycle' {
            CW "On vide la corbeille..." 'hi'
            try { Clear-RecycleBin -Force -EA Stop; CW "  Corbeille videe." 'ok' } catch { CW "  La corbeille etait deja vide." 'warn' }
        }
        'wu' {
            CW "On nettoie les anciens fichiers de mise a jour..." 'hi'
            Stop-Service wuauserv -Force -EA SilentlyContinue
            $g=Clean-Path "$env:SystemRoot\SoftwareDistribution\Download" "Fichiers de mise a jour"
            Start-Service wuauserv -EA SilentlyContinue
            $Script:totalFreed+=$g
        }
        'all' {
            if (-not (Dlg-YN "On lance le grand nettoyage ?`n(Corbeille + fichiers temporaires + fichiers de mise a jour)")) { return }
            $g=0
            $g+=Clean-Path "$env:TEMP" "Fichiers temporaires"
            $g+=Clean-Path "$env:SystemRoot\Temp" "Temporaires Windows"
            Stop-Service wuauserv -Force -EA SilentlyContinue
            $g+=Clean-Path "$env:SystemRoot\SoftwareDistribution\Download" "Fichiers de mise a jour"
            Start-Service wuauserv -EA SilentlyContinue
            $g+=Clean-Path "$env:SystemRoot\Logs" "Journaux Windows"
            try { Clear-RecycleBin -Force -EA SilentlyContinue; CW "  Corbeille videe." 'ok' } catch {}
            $Script:totalFreed+=$g
            CW ""; CW ("GRAND NETTOYAGE TERMINE : $([math]::Round($g,0)) Mo liberes !") 'hi'
            Write-Log "NETTOYAGE $([math]::Round($g,0))Mo"
        }
    }
}

# ════════════════════════════════════════════════════════════════
#  ONGLET 3 : BILAN DE SANTE
# ════════════════════════════════════════════════════════════════
$t3 = New-Tab "Bilan de sante"; $TC.TabPages.Add($t3)
$t3.Controls.Add((New-Label "Votre PC est-il en forme ?" 0 4 500 28 $true))
$t3.Controls.Add((New-Label "Un petit controle rapide, avec des conseils si besoin." 0 36 600 24))

$bBilan = New-Btn "Lancer le bilan" 0 74 220 42 $Teal
$t3.Controls.Add($bBilan)

$pnlBilan = [System.Windows.Forms.Panel]::new()
$pnlBilan.Location=[Drawing.Point]::new(0,132); $pnlBilan.Size=[Drawing.Size]::new(810,330); $pnlBilan.AutoScroll=$true
$t3.Controls.Add($pnlBilan)

function Add-Check { param($y,$titre,$etat,$verdict,$conseil)
    $card=New-Card 0 $y 780 62; $pnlBilan.Controls.Add($card)
    $col= switch($verdict){ 'ok'{$Green} 'warn'{$Orange} 'ko'{$Red} }
    $puce=[System.Windows.Forms.Panel]::new(); $puce.Location=[Drawing.Point]::new(16,20); $puce.Size=[Drawing.Size]::new(22,22); $puce.BackColor=$col
    $card.Controls.Add($puce)
    $lt=New-Label $titre 52 8 280 24 $true; $lt.BackColor=$CardBg; $card.Controls.Add($lt)
    $le=New-Label $etat 52 32 280 22; $le.ForeColor=$Mute; $le.BackColor=$CardBg; $card.Controls.Add($le)
    $lc=New-Label $conseil 344 8 424 48; $lc.ForeColor=$col; $lc.BackColor=$CardBg; $card.Controls.Add($lc)
}

$bBilan.Add_Click({ param($sender,$e)
    $pnlBilan.Controls.Clear()
    $y=0
    # 1. Espace disque
    $d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA SilentlyContinue
    if ($d) {
        $freeP=[int](($d.FreeSpace/$d.Size)*100)
        if ($freeP -ge 20) { Add-Check $y "Espace de stockage" "$freeP% d'espace libre" 'ok' "Parfait, il reste de la place." }
        elseif ($freeP -ge 8) { Add-Check $y "Espace de stockage" "$freeP% d'espace libre" 'warn' "Ca se remplit. Faites un nettoyage." }
        else { Add-Check $y "Espace de stockage" "$freeP% d'espace libre" 'ko' "Presque plein ! Faites le menage sans tarder." }
        $y+=72
    }
    # 2. Memoire
    $os2=Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    $ramUseP=[int]((($os2.TotalVisibleMemorySize-$os2.FreePhysicalMemory)/$os2.TotalVisibleMemorySize)*100)
    if ($ramUseP -lt 75) { Add-Check $y "Memoire (RAM)" "$ramUseP% utilisee" 'ok' "Tout va bien." }
    elseif ($ramUseP -lt 90) { Add-Check $y "Memoire (RAM)" "$ramUseP% utilisee" 'warn' "Fermez les programmes inutiles." }
    else { Add-Check $y "Memoire (RAM)" "$ramUseP% utilisee" 'ko' "Saturee. Un redemarrage aiderait." }
    $y+=72
    # 3. Dernier redemarrage
    $up=(Get-Date)-$os2.LastBootUpTime
    if ($up.Days -lt 4) { Add-Check $y "Dernier redemarrage" "il y a $($up.Days) jour(s)" 'ok' "Bien, votre PC est frais." }
    elseif ($up.Days -lt 10) { Add-Check $y "Dernier redemarrage" "il y a $($up.Days) jours" 'warn' "Pensez a redemarrer bientot." }
    else { Add-Check $y "Dernier redemarrage" "il y a $($up.Days) jours" 'ko' "Redemarrez : ca fait longtemps." }
    $y+=72
    # 4. Internet
    $ping = Test-Connection 1.1.1.1 -Count 1 -Quiet -EA SilentlyContinue
    if ($ping) { Add-Check $y "Connexion Internet" "connecte" 'ok' "Vous etes bien en ligne." }
    else { Add-Check $y "Connexion Internet" "pas de reponse" 'warn' "Verifiez le Wi-Fi ou le cable." }
    $y+=72
    $pnlBilan.Refresh()
    Write-Log "BILAN"
})

# ════════════════════════════════════════════════════════════════
#  ONGLET 4 : CONSEILS
# ════════════════════════════════════════════════════════════════
$t4 = New-Tab "Conseils"; $TC.TabPages.Add($t4)
$t4.Controls.Add((New-Label "Quelques bons reflexes pour garder un PC en forme" 0 4 700 28 $true))

$conseils = @(
    @("Redemarrez une fois par semaine", "Eteindre et rallumer vide la memoire et regle beaucoup de petits ralentissements."),
    @("Faites le menage une fois par mois", "Videz la corbeille et les fichiers temporaires : c'est l'onglet 'Faire le menage'."),
    @("Gardez Windows a jour", "Les mises a jour corrigent des failles et des bugs. Ne les repoussez pas trop."),
    @("N'installez que ce que vous connaissez", "Evitez les logiciels 'gratuits' douteux et les barres d'outils : c'est la 1ere cause de PC lent."),
    @("Un antivirus suffit", "Windows en integre un (Defender). Inutile d'en cumuler plusieurs, ils se genent."),
    @("Ne remplissez pas le disque a ras bord", "Laissez toujours 10 a 15% d'espace libre pour que Windows respire.")
)
$yc = 46
foreach ($cn in $conseils) {
    $card=New-Card 0 $yc 800 60; $t4.Controls.Add($card)
    $puce=[System.Windows.Forms.Panel]::new(); $puce.Location=[Drawing.Point]::new(16,23); $puce.Size=[Drawing.Size]::new(14,14); $puce.BackColor=$Teal
    $card.Controls.Add($puce)
    $card.Controls.Add((New-Label $cn[0] 46 6 740 24 $true))
    $ld=New-Label $cn[1] 46 30 740 24; $ld.ForeColor=$Mute; $card.Controls.Add($ld)
    $yc += 64
}
$bWU = New-Btn "Ouvrir les mises a jour Windows" 0 ($yc+2) 300 40 $Blue
$bWU.Add_Click({ try { Start-Process "ms-settings:windowsupdate" } catch {} })
$t4.Controls.Add($bWU)

# ════════════════════════════════════════════════════════════════
#  PAGE D'ACCUEIL
# ════════════════════════════════════════════════════════════════
function Draw-TileIcon { param($g,$type,$color,$x,$y,$sz) Draw-Icon $g $type $color $x $y $sz }

$Accueil = [System.Windows.Forms.Panel]::new()
$Accueil.Location=[Drawing.Point]::new(0,64); $Accueil.Size=[Drawing.Size]::new(900,580); $Accueil.BackColor=$BgCol
$F.Controls.Add($Accueil); $Accueil.BringToFront()

$wl = New-Label "Bonjour !" 40 30 500 40 $true
$wl.Font=[Drawing.Font]::new("Segoe UI",22,[Drawing.FontStyle]::Bold); $Accueil.Controls.Add($wl)
$ws = New-Label "Que souhaitez-vous faire aujourd'hui ?" 42 76 600 26; $ws.ForeColor=$Mute; $Accueil.Controls.Add($ws)

$tiles = @(
    @{ t="Mon ordinateur"; s="Voir les infos de votre PC"; tab=0; c=$Blue;   ic="pc" },
    @{ t="Faire le menage"; s="Liberer de l'espace"; tab=1; c=$Green;  ic="broom" },
    @{ t="Bilan de sante"; s="Verifier que tout va bien"; tab=2; c=$Teal;   ic="health" },
    @{ t="Conseils"; s="Bien entretenir son PC"; tab=3; c=$Purple; ic="bulb" }
)
$tw=396; $th=150; $gap=24; $ox=40; $oy=126
for ($i=0; $i -lt $tiles.Count; $i++) {
    $ti=$tiles[$i]; $col=$i%2; $row=[math]::Floor($i/2)
    $px=$ox+$col*($tw+$gap); $py=$oy+$row*($th+$gap)
    $tile=[System.Windows.Forms.Panel]::new()
    $tile.Location=[Drawing.Point]::new($px,$py); $tile.Size=[Drawing.Size]::new($tw,$th)
    $tile.BackColor=$CardBg; $tile.Cursor='Hand'; $tile.Tag=$ti

    $iconP=[System.Windows.Forms.Panel]::new()
    $iconP.Location=[Drawing.Point]::new(28,34); $iconP.Size=[Drawing.Size]::new(64,64); $iconP.BackColor=$CardBg
    $iconP.Tag=@{ ic=$ti.ic; c=$ti.c }
    $iconP.Add_Paint({ param($sndr,$e) Draw-Icon $e.Graphics $sndr.Tag.ic $sndr.Tag.c 8 6 50 })
    $tile.Controls.Add($iconP)

    $tl=New-Label $ti.t 116 38 262 30 $true; $tl.Font=[Drawing.Font]::new("Segoe UI",14,[Drawing.FontStyle]::Bold); $tile.Controls.Add($tl)
    $sl=New-Label $ti.s 116 74 262 40; $sl.ForeColor=$Mute; $tile.Controls.Add($sl)

    $enter={ param($sndr,$e)
        $x=$sndr; while ($x -and -not ($x.Tag -is [hashtable] -and $x.Tag.ContainsKey('tab'))) { $x=$x.Parent }
        if ($x) { $x.BackColor=[Drawing.Color]::FromArgb(238,246,252) }
    }
    $leave={ param($sndr,$e)
        $x=$sndr; while ($x -and -not ($x.Tag -is [hashtable] -and $x.Tag.ContainsKey('tab'))) { $x=$x.Parent }
        if ($x) { $x.BackColor=[Drawing.Color]::White }
    }
    $click={ param($sndr,$e)
        $x=$sndr; while ($x -and -not ($x.Tag -is [hashtable] -and $x.Tag.ContainsKey('tab'))) { $x=$x.Parent }
        if ($x) { $Accueil.Visible=$false; $TC.SelectedIndex=$x.Tag.tab; $TC.BringToFront() }
    }
    $tile.Add_MouseEnter($enter); $tile.Add_MouseLeave($leave); $tile.Add_Click($click)
    foreach ($ch in $tile.Controls) { $ch.Add_MouseEnter($enter); $ch.Add_Click($click) }
    $Accueil.Controls.Add($tile)
}
$foot = New-Label "PC Malin  -  par Davy Faugere" 42 530 600 24; $foot.ForeColor=$Mute; $Accueil.Controls.Add($foot)

$btnHome.Add_Click({ $Accueil.Visible=$true; $Accueil.BringToFront() })

Write-Log "SESSION"
$F.ShowDialog() | Out-Null
