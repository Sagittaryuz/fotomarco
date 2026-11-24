"""Register the separate Business Google callback without changing existing schemes."""
import pathlib
import plistlib
import re
import sys

app = pathlib.Path(sys.argv[1])
firebase = app / 'GoogleService-Info.plist'
if not firebase.exists():
    if '--required' in sys.argv[2:]:
        raise SystemExit('Business Firebase configuration is required for signing')
    print('Business Firebase configuration not present; skipping callback')
    raise SystemExit(0)
with firebase.open('rb') as file:
    config = plistlib.load(file)
client = config.get('CLIENT_ID', '')
scheme = config.get('REVERSED_CLIENT_ID', '')
if not re.fullmatch(r'[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com', client):
    raise SystemExit('Business Google client ID is missing or invalid')
if scheme != '.'.join(reversed(client.split('.'))):
    raise SystemExit('Business callback scheme does not match its client ID')
info_path = app / 'Info.plist'
with info_path.open('rb') as file:
    info = plistlib.load(file)
if info.get('CFBundleIdentifier') != 'br.com.momentra.camera':
    raise SystemExit('Unexpected bundle identifier')
types = info.setdefault('CFBundleURLTypes', [])
if not any(scheme in item.get('CFBundleURLSchemes', []) for item in types):
    types.append({'CFBundleURLSchemes': [scheme]})
with info_path.open('wb') as file:
    plistlib.dump(info, file)
print('Business callback configured')
