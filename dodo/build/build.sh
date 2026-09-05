#!/usr/bin/env bash
# Construit Dodo-Installateur.exe et Dodo-Installateur.cmd depuis les sources.
# Prerequis : python3, zip, mono-mcs (pour l'exe).
set -euo pipefail
cd "$(dirname "$0")/.."          # -> dodo/
OUT="../dist"
mkdir -p "$OUT" build/tmp
rm -rf build/tmp/*

echo "[1/4] Constitution de la charge utile (src + tests + docs) ..."
mkdir -p build/tmp/payload
cp -r src tests build/tmp/payload/
cp README.md build/tmp/payload/ 2>/dev/null || true
mkdir -p build/tmp/payload/docs && cp docs/*.md build/tmp/payload/docs/
( cd build/tmp/payload && zip -rq ../payload.zip . )
echo "      -> $(wc -c < build/tmp/payload.zip) octets compresses"

echo "[2/4] Injection dans l'assistant (UTF-8 avec BOM) ..."
python3 - <<'PYEOF'
import base64
b64 = base64.b64encode(open('build/tmp/payload.zip','rb').read()).decode('ascii')
src = open('src/Assistant-Dodo.ps1', encoding='utf-8-sig').read()
assert 'AAPAYLOADAA' in src, "marqueur de charge utile introuvable dans Assistant-Dodo.ps1"
out = src.replace('AAPAYLOADAA', b64)
with open('build/tmp/assistant.ps1','wb') as f:
    f.write(b'\xef\xbb\xbf')                 # BOM : indispensable pour les accents sous PS 5.1
    f.write(out.encode('utf-8'))
print("      -> assistant.ps1 : %d octets" % len(out))
PYEOF

echo "[3/4] Assemblage de Dodo-Installateur.cmd ..."
python3 - <<'PYEOF'
head = open('build/header.cmd','rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
body = open('build/tmp/assistant.ps1','rb').read()
if body.startswith(b'\xef\xbb\xbf'):
    body = body[3:]                          # le BOM est reintroduit a l'extraction
open('../dist/Dodo-Installateur.cmd','wb').write(head + body)
PYEOF
echo "      -> dist/Dodo-Installateur.cmd ($(wc -c < ../dist/Dodo-Installateur.cmd) octets)"

echo "[4/4] Compilation de Dodo-Installateur.exe ..."
if command -v mcs >/dev/null 2>&1; then
    ICON=""
    [ -f ../assets/pcmalin.ico ] && ICON="-win32icon:../assets/pcmalin.ico"
    mcs -target:winexe -optimize+ $ICON \
        -resource:build/tmp/assistant.ps1,assistant.ps1 \
        -r:System.Windows.Forms.dll \
        -out:"$OUT/Dodo-Installateur.exe" build/launcher.cs
    echo "      -> dist/Dodo-Installateur.exe ($(wc -c < "$OUT/Dodo-Installateur.exe") octets)"
else
    echo "      mcs introuvable (apt install mono-mcs) - exe non construit."
fi

rm -rf build/tmp
echo "Termine. Livrables dans dist/"
