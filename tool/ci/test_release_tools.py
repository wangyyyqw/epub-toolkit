import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from release_notes import changelog_section, generate


class ReleaseToolsTest(unittest.TestCase):
    def test_native_builds_regenerate_release_plugin_registrants(self):
        workflow = (Path(__file__).resolve().parents[2] /
                    ".github/workflows/release-builds.yml").read_text()
        commands = [line for line in workflow.splitlines() if " flutter build " in line]
        self.assertEqual(len(commands), 4)
        for command in commands:
            self.assertIn("--release", command)
            self.assertNotIn("--no-pub", command)

    def test_changelog_has_exact_version_and_stops_at_next_release(self):
        self.assertEqual(changelog_section(
            "# Log\n## 1.6.3 - 2026-09-17\n\nNew\n\n## 1.6.2\nOld\n", "1.6.3"
        ), "New")
        with self.assertRaises(ValueError):
            changelog_section("## 1.6.30\nWrong", "1.6.3")

    def test_complete_assets_generate_hashes_and_traceability(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for suffix in ["android-v1.6.3+37.apk", "macos-v1.6.3+37.zip",
                           "windows-v1.6.3+37-setup.exe", "ios-v1.6.3+37-unsigned.zip"]:
                (root / f"epub-toolkit-{suffix}").write_bytes(b"test artifact")
            body = generate(root, "1.6.3", "37", "abc123", "https://example.invalid/run",
                            "## 1.6.3\n\nChanges\n", {"jobs": []})
            self.assertIn("Changes", body)
            self.assertIn("abc123", body)
            metadata = json.loads((root / "build-metadata.json").read_text())
            self.assertEqual(len(metadata["assets"]), 4)
            expected = hashlib.sha256(b"test artifact").hexdigest()
            self.assertTrue(all(a["sha256"] == expected for a in metadata["assets"]))
            self.assertEqual(len((root / "SHA256SUMS.txt").read_text().splitlines()), 4)

    def test_partial_artifacts_cannot_publish(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "epub-toolkit-android-v1.6.3+37.apk").write_bytes(b"apk")
            with self.assertRaisesRegex(ValueError, "exactly"):
                generate(root, "1.6.3", "37", "abc", "url", "## 1.6.3\nChanges", {})
            self.assertFalse((root / "SHA256SUMS.txt").exists())

    def test_runner_propagates_failure_and_retains_logs(self):
        script = Path(__file__).with_name("run_logged.py").resolve()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            summary = root / "summary.md"
            result = subprocess.run(
                [sys.executable, str(script), "probe", sys.executable, "-c",
                 "print('failure-marker'); raise SystemExit(7)"],
                cwd=root, env={**os.environ, "GITHUB_STEP_SUMMARY": str(summary)},
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 7)
            self.assertIn("failure-marker", (root / "build-logs/probe.log").read_text())
            self.assertIn("exit `7`", summary.read_text())


if __name__ == "__main__":
    unittest.main()
