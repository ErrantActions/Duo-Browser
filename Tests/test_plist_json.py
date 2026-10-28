import base64
import datetime
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / ".github" / "scripts" / "plist-json.py"


class PlistMetadataTests(unittest.TestCase):
    def test_dates_certificate_data_and_entitlements_are_normalized(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "profile.plist"
            output = Path(directory) / "private.json"
            source.write_bytes(plistlib.dumps({
                "ExpirationDate": datetime.datetime(2030, 1, 1),
                "DeveloperCertificates": [b"test-certificate"],
                "Entitlements": {"get-task-allow": False},
            }))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(source), str(output)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            data = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(data["ExpirationDate"], "2030-01-01T00:00:00+00:00")
            self.assertEqual(data["DeveloperCertificates"], [
                base64.b64encode(b"test-certificate").decode("ascii")
            ])
            self.assertFalse(data["Entitlements"]["get-task-allow"])

    def test_invalid_plist_does_not_echo_private_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "invalid.plist"
            output = Path(directory) / "private.json"
            source.write_text("fixture-private-value", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(source), str(output)],
                capture_output=True, text=True, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("fixture-private-value", result.stdout + result.stderr)
            self.assertFalse(output.exists())

    def test_non_dictionary_root_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "array.plist"
            output = Path(directory) / "private.json"
            source.write_bytes(plistlib.dumps(["not", "metadata"]))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(source), str(output)],
                capture_output=True, text=True, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
