import os
import pathlib
import plistlib
import re
import sys

client = os.environ.get('MOMENTRA_GOOGLE_IOS_CLIENT_ID', '')
reverse = os.environ.get('MOMENTRA_GOOGLE_IOS_REVERSED_ID', '')
if not re.fullmatch(r'[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com', client):
    raise SystemExit('Google iOS client ID is missing or invalid')
if reverse != '.'.join(reversed(client.split('.'))):
    raise SystemExit('Google iOS URL scheme does not match its client ID')
path = pathlib.Path(sys.argv[1])
with path.open('rb') as f:
    info = plistlib.load(f)
if info.get('CFBundleIdentifier') != 'br.com.momentra.camera':
    raise SystemExit('Unexpected app bundle identifier')
info['GIDClientID'] = client
types = info.setdefault('CFBundleURLTypes', [])
if not any(reverse in item.get('CFBundleURLSchemes', []) for item in types):
    types.append({'CFBundleURLSchemes': [reverse]})
if not any('momentra' in item.get('CFBundleURLSchemes', []) for item in types):
    types.append({'CFBundleURLSchemes': ['momentra']})
with path.open('wb') as f:
    plistlib.dump(info, f)
print('Google iOS client configuration applied')
