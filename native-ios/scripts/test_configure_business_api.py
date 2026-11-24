import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('configure-business-api.py')

class BusinessAPIConfigTests(unittest.TestCase):
    def run_config(self, path, endpoint, *extra):
        env = dict(os.environ, PHOTOMARK_BUSINESS_API=endpoint)
        return subprocess.run([sys.executable, str(SCRIPT), str(path), *extra], env=env, capture_output=True, text=True)

    def test_configuration_and_preserved_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'Info.plist'
            path.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'br.com.momentra.camera', 'CFBundleVersion': '99'}))
            self.assertEqual(self.run_config(path, 'https://business.example/', '--required').returncode, 0)
            info = plistlib.loads(path.read_bytes())
            self.assertEqual(info['PhotomarkBusinessAPI'], 'https://business.example')
            self.assertEqual(info['CFBundleVersion'], '99')
            self.assertNotEqual(self.run_config(path, '', '--required').returncode, 0)
            for endpoint in ['http://business.example', 'https://evil.example/path', 'https://user:pass@business.example']:
                self.assertNotEqual(self.run_config(path, endpoint, '--required').returncode, 0)
            self.assertEqual(plistlib.loads(path.read_bytes()), info)

    def test_wrong_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'Info.plist'
            path.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'wrong'}))
            self.assertNotEqual(self.run_config(path, 'https://business.example').returncode, 0)
            self.assertNotIn('PhotomarkBusinessAPI', plistlib.loads(path.read_bytes()))

if __name__ == '__main__':
    unittest.main()
