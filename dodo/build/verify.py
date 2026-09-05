#!/usr/bin/env python3
"""Verifie les livrables Dodo produits par build.sh.

Controle le vrai artefact, pas les sources : on extrait l'assistant du .cmd,
on decode la charge utile embarquee et on verifie qu'elle est complete. Le
meme contenu est embarque dans l'exe (meme fichier, meme etape de build).
"""
import base64
import io
import os
import re
import sys
import zipfile

CMD = 'dist/Dodo-Installateur.cmd'
EXE = 'dist/Dodo-Installateur.exe'
ATTENDUS = [
    'src/Assistant-Dodo.ps1', 'src/DodoCore.ps1', 'src/DodoRuntime.ps1', 'src/DodoSpeech.ps1',
    'src/Install-Dodo.ps1', 'src/Invoke-DodoEnforce.ps1', 'src/Show-DodoWarning.ps1',
    'src/Get-DodoStatus.ps1', 'src/Add-DodoException.ps1', 'src/Uninstall-Dodo.ps1',
    'src/dodo.config.json', 'src/dodo.messages.json', 'src/run-notify-hidden.vbs',
    'tests/Test-DodoLogic.ps1', 'tests/Test-DodoE2E.ps1',
]
ACCENTS = ['période scolaire', 'téléphone', 'Désinstaller', 'Tester une soirée']

erreurs = []


def check(cond, msg):
    print(('  OK   ' if cond else '  ECHEC ') + msg)
    if not cond:
        erreurs.append(msg)


print('Verification des livrables Dodo')

check(os.path.isfile(CMD), CMD + ' present')
check(os.path.isfile(EXE), EXE + ' present')
if erreurs:
    sys.exit(1)

with open(EXE, 'rb') as f:
    tete = f.read(2)
check(tete == b'MZ', 'Dodo-Installateur.exe est bien un executable Windows (signature MZ)')
check(os.path.getsize(EXE) > 50_000, 'exe de taille plausible (%d octets)' % os.path.getsize(EXE))

raw = open(CMD, 'rb').read()
marqueur = b'ZZ_PSSTART_ZZ\r\n'
check(marqueur in raw, 'marqueur ZZ_PSSTART_ZZ present dans le .cmd')
if erreurs:
    sys.exit(1)

corps = raw[raw.index(marqueur) + len(marqueur):]
try:
    txt = corps.decode('utf-8')
    check(True, 'assistant decodable en UTF-8 (%d octets)' % len(corps))
except UnicodeDecodeError as e:
    check(False, 'assistant decodable en UTF-8 : ' + str(e))
    sys.exit(1)

for mot in ACCENTS:
    check(mot in txt, "libelle accentue present : « %s »" % mot)

m = re.search(r"\$PAYLOAD = '([A-Za-z0-9+/=]+)'", txt)
check(m is not None, 'charge utile embarquee trouvee')
if not m:
    sys.exit(1)

data = base64.b64decode(m.group(1))
check(len(data) > 20_000, 'charge utile de taille plausible (%d octets)' % len(data))

try:
    z = zipfile.ZipFile(io.BytesIO(data))
    abime = z.testzip()
    check(abime is None, 'archive interne intacte' + ('' if abime is None else ' (corrompu : %s)' % abime))
    noms = set(z.namelist())
    for n in ATTENDUS:
        check(n in noms, 'present dans la charge utile : ' + n)
except zipfile.BadZipFile as e:
    check(False, 'archive interne lisible : ' + str(e))

print()
if erreurs:
    print('%d controle(s) en echec.' % len(erreurs))
    sys.exit(1)
print('Tous les controles sont verts.')
