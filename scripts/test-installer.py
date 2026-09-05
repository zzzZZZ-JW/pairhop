#!/usr/bin/env python3
"""Offline installer gate tests. Only a temporary script copy uses stub commands.

The production installer has fixed system tool paths, publisher identity and
binary hash. Nothing in these tests installs a service or changes macOS settings.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parent.parent


class InstallerTests(unittest.TestCase):
    def run_fixture(self, *, download_ok=True, checksum_ok=True, signature_ok=True):
        with tempfile.TemporaryDirectory(prefix="pairhop-installer-test.") as directory:
            root = Path(directory)
            payload = root / "payload"
            payload.write_text('#!/bin/bash\nprintf "%s" "$1" > "$PAIRHOP_TEST_EXECUTED"\n')
            digest = hashlib.sha256(payload.read_bytes()).hexdigest()
            curl = root / "curl"
            curl.write_text('#!/bin/bash\n'
                            + ('exit 22\n' if not download_ok else
                               'while [[ "$#" -gt 0 ]]; do\n'
                               '  if [[ "$1" == --output ]]; then cp "$PAIRHOP_TEST_PAYLOAD" "$2"; exit; fi\n'
                               '  shift\ndone\nexit 2\n'))
            codesign = root / "codesign"
            codesign.write_text('#!/bin/bash\necho checked > "$PAIRHOP_TEST_SIGNATURE"\n'
                                + ('exit 0\n' if signature_ok else 'exit 1\n'))
            for path in [curl, codesign]:
                path.chmod(0o700)
            script = (PROJECT / "install.sh").read_text()
            import re
            script = re.sub(r"local expected_sha256='[^']*'", "local expected_sha256='" + (digest if checksum_ok else '0' * 64) + "'", script)
            # These dependency substitutions exist in this throwaway copy only.
            script = script.replace('/usr/bin/curl', '"' + str(curl) + '"')
            script = script.replace('/usr/bin/codesign', '"' + str(codesign) + '"')
            path = root / "install.sh"
            path.write_text(script)
            marker = root / "executed"
            signature_marker = root / "signature"
            staging = root / "temporary"
            staging.mkdir()
            env = dict(os.environ, TMPDIR=str(staging) + '/', PAIRHOP_TEST_PAYLOAD=str(payload),
                       PAIRHOP_TEST_EXECUTED=str(marker), PAIRHOP_TEST_SIGNATURE=str(signature_marker))
            result = subprocess.run(['/bin/bash', str(path)], env=env, capture_output=True, text=True)
            self.assertEqual(list(staging.iterdir()), [], msg=result.stderr)
            return result.returncode, marker.read_text() if marker.exists() else None, signature_marker.exists()

    def test_success_runs_only_after_both_checks(self):
        self.assertEqual(self.run_fixture(), (0, 'install', True))

    def test_failed_download_never_executes(self):
        status, executed, signature = self.run_fixture(download_ok=False)
        self.assertNotEqual(status, 0)
        self.assertIsNone(executed)
        self.assertFalse(signature)

    def test_hash_mismatch_never_executes_or_checks_signature(self):
        status, executed, signature = self.run_fixture(checksum_ok=False)
        self.assertNotEqual(status, 0)
        self.assertIsNone(executed)
        self.assertFalse(signature)

    def test_signature_failure_never_executes(self):
        status, executed, signature = self.run_fixture(signature_ok=False)
        self.assertNotEqual(status, 0)
        self.assertIsNone(executed)
        self.assertTrue(signature)


if __name__ == '__main__':
    unittest.main(verbosity=2)
