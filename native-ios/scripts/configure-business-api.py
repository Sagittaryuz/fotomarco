"""Configure the public Business API endpoint before signing an iOS package."""
import argparse
import os
import pathlib
import plistlib
from urllib.parse import urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('plist', type=pathlib.Path)
parser.add_argument('--required', action='store_true')
args = parser.parse_args()
endpoint = os.environ.get('PHOTOMARK_BUSINESS_API', '').strip()
if not endpoint:
    if args.required:
        raise SystemExit('Business API endpoint is required for this signing candidate')
    print('Business API is not configured in this draft')
    raise SystemExit(0)
parts = urlsplit(endpoint)
if (parts.scheme != 'https' or not parts.hostname or parts.username is not None or parts.password is not None or
        parts.port is not None or parts.path not in ('', '/') or parts.query or parts.fragment):
    raise SystemExit('Business API must be an HTTPS origin without credentials or path')
with args.plist.open('rb') as file:
    info = plistlib.load(file)
if info.get('CFBundleIdentifier') != 'br.com.momentra.camera':
    raise SystemExit('Unexpected app bundle identifier')
info['PhotomarkBusinessAPI'] = endpoint.rstrip('/')
with args.plist.open('wb') as file:
    plistlib.dump(info, file)
print('Business API public endpoint configured')
