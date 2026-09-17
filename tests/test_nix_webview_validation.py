#!/usr/bin/env python3
"""Regression tests for the Nix launcher's webview-origin validation."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = REPO_ROOT / "nix" / "verify-webview-origin.py"


class WebviewOriginValidationTests(unittest.TestCase):
    def validate(self, html: str) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile("w", suffix=".html") as fixture:
            fixture.write(html)
            fixture.flush()
            return subprocess.run(
                [sys.executable, str(VALIDATOR), Path(fixture.name).as_uri()],
                check=False,
                capture_output=True,
                text=True,
            )

    def test_accepts_current_chatgpt_title(self) -> None:
        result = self.validate("<title>ChatGPT</title><div class='startup-loader'>")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_accepts_legacy_codex_title(self) -> None:
        result = self.validate("<title>Codex</title><div class='startup-loader'>")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unknown_title(self) -> None:
        result = self.validate("<title>Other</title><div class='startup-loader'>")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("an accepted app title", result.stderr)

    def test_rejects_missing_startup_marker(self) -> None:
        result = self.validate("<title>ChatGPT</title>")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("startup-loader", result.stderr)


if __name__ == "__main__":
    unittest.main()
