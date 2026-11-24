import pathlib
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('configure-business-auth.py')

class BusinessCallbackTests(unittest.TestCase):
    def test_callback_preserves_existing_schemes_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory)
            info = {'CFBundleIdentifier': 'br.com.momentra.camera',
                    'CFBundleURLTypes': [{'CFBundleURLSchemes': ['momentra', 'existing.google']}]}
            config = {'CLIENT_ID': '123-abc.apps.googleusercontent.com',
                      'REVERSED_CLIENT_ID': 'com.googleusercontent.apps.123-abc'}
            for name, value in [('Info.plist', info), ('GoogleService-Info.plist', config)]:
                with (app / name).open('wb') as file:
                    plistlib.dump(value, file)
            for _ in range(2):
                subprocess.run(['python', str(SCRIPT), str(app), '--required'], check=True, capture_output=True)
            with (app / 'Info.plist').open('rb') as file:
                updated = plistlib.load(file)
            schemes = [scheme for item in updated['CFBundleURLTypes'] for scheme in item['CFBundleURLSchemes']]
            self.assertEqual(schemes.count(config['REVERSED_CLIENT_ID']), 1)
            self.assertIn('momentra', schemes)
            self.assertIn('existing.google', schemes)

    def test_required_configuration_is_not_optional_for_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(['python', str(SCRIPT), directory, '--required'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

if __name__ == '__main__':
    unittest.main()
