# Genere assets/banner.png pour le repo pc-malin
# Usage :  powershell -ExecutionPolicy Bypass -File make-banner.ps1 -Repo "C:\dev\pcmalin-repo"
param([string]$Repo = "C:\dev\pcmalin-repo")

Add-Type -AssemblyName System.Drawing

$W = 1280; $H = 400
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'

# Degrade vertical turquoise -> bleu
$rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
$top = [System.Drawing.Color]::FromArgb(38, 196, 196)
$bot = [System.Drawing.Color]::FromArgb(45, 120, 210)
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bot, 90)
$g.FillRectangle($grad, $rect)

# Etoiles discretes en fond
$sparkle = {
    param($cx, $cy, $sz)
    $pts = @(
        (New-Object System.Drawing.PointF($cx, ($cy - $sz))),
        (New-Object System.Drawing.PointF(($cx + $sz * 0.28), ($cy - $sz * 0.28))),
        (New-Object System.Drawing.PointF(($cx + $sz), $cy)),
        (New-Object System.Drawing.PointF(($cx + $sz * 0.28), ($cy + $sz * 0.28))),
        (New-Object System.Drawing.PointF($cx, ($cy + $sz))),
        (New-Object System.Drawing.PointF(($cx - $sz * 0.28), ($cy + $sz * 0.28))),
        (New-Object System.Drawing.PointF(($cx - $sz), $cy)),
        (New-Object System.Drawing.PointF(($cx - $sz * 0.28), ($cy - $sz * 0.28)))
    )
    $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38, 255, 255, 255))
    $g.FillPolygon($br, $pts)
    $br.Dispose()
}
$rand = New-Object System.Random(7)
for ($i = 0; $i -lt 14; $i++) {
    & $sparkle $rand.Next(40, $W - 40) $rand.Next(30, $H - 30) $rand.Next(6, 17)
}

# Icone (preview 512px deja dans le repo) a gauche, avec ombre douce
$icoPath = Join-Path $Repo "assets\pcmalin_preview.png"
if (Test-Path $icoPath) {
    $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 0, 0, 0))
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddRectangle((New-Object System.Drawing.Rectangle(96, 76, 280, 280)))
    $g.FillPath($shadow, $gp)
    $ico = [System.Drawing.Image]::FromFile($icoPath)
    $g.DrawImage($ico, 88, 64, 280, 280)
    $ico.Dispose(); $shadow.Dispose()
}

# Textes
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$pale1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 248, 250))
$pale2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 240, 244))
$f1 = New-Object System.Drawing.Font("Segoe UI", 62, [System.Drawing.FontStyle]::Bold)
$f2 = New-Object System.Drawing.Font("Segoe UI", 25)
$f3 = New-Object System.Drawing.Font("Segoe UI", 19)
$g.DrawString("PC Malin", $f1, $white, 420, 90)
$g.DrawString("L'entretien facile de votre ordinateur Windows", $f2, $pale1, 428, 215)
$g.DrawString("Gratuit  -  Un seul fichier  -  Vos documents jamais touches", $f3, $pale2, 430, 275)

# Sauvegarde
$out = Join-Path $Repo "assets\banner.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $grad.Dispose()
$white.Dispose(); $pale1.Dispose(); $pale2.Dispose()
$f1.Dispose(); $f2.Dispose(); $f3.Dispose()

Write-Host "OK : $out ($((Get-Item $out).Length) octets)"
