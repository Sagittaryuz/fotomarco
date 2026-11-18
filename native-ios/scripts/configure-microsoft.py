import os
import pathlib
import plistlib
import sys
import uuid

client = os.environ.get('MOMENTRA_MICROSOFT_CLIENT_ID', '')
if not client:
    print('OneDrive connection disabled: no public Microsoft client ID supplied')
    raise SystemExit(0)
try:
    client = str(uuid.UUID(client))
except ValueError:
    raise SystemExit('Invalid Microsoft public client ID') from None

path = pathlib.Path(sys.argv[1])
with path.open('rb') as file:
    info = plistlib.load(file)
if info.get('CFBundleIdentifier') != 'br.com.momentra.camera':
    raise SystemExit('Unexpected app bundle identifier')

info['MomentraMicrosoftClientID'] = client
types = info.setdefault('CFBundleURLTypes', [])
scheme = 'msauth.br.com.momentra.camera'
if not any(scheme in entry.get('CFBundleURLSchemes', []) for entry in types):
    types.append({'CFBundleURLSchemes': [scheme]})
with path.open('wb') as file:
    plistlib.dump(info, file)
print('Microsoft iOS public client configuration applied')
