#!/usr/bin/env bash
# Construit PC-Malin.cmd et PC-Malin.exe depuis les sources.
# Prérequis : python3, mono-mcs (pour l'exe).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p dist

echo "[1/3] Assemblage de PC-Malin.cmd ..."
cat src/header.cmd src/pcmalin.ps1 > dist/PC-Malin.cmd
echo "      -> dist/PC-Malin.cmd ($(wc -c < dist/PC-Malin.cmd) octets)"

echo "[2/3] Préparation du script embarqué (UTF-8 BOM) ..."
python3 - << 'PYEOF'
body = open('src/pcmalin.ps1', encoding='utf-8').read()
with open('embed.ps1', 'wb') as f:
    f.write(b'\xef\xbb\xbf')
    f.write(body.encode('utf-8'))
PYEOF

echo "[3/3] Compilation de PC-Malin.exe ..."
if command -v mcs >/dev/null 2>&1; then
    mcs -target:winexe -optimize+ \
        -win32icon:assets/pcmalin.ico \
        -resource:embed.ps1,pcmalin.ps1 \
        -r:System.Windows.Forms.dll \
        -out:dist/PC-Malin.exe src/launcher.cs
    echo "      -> dist/PC-Malin.exe ($(wc -c < dist/PC-Malin.exe) octets)"
else
    echo "      mcs introuvable (apt install mono-mcs) — exe non construit."
fi
rm -f embed.ps1

echo "Terminé. Livrables dans dist/"
