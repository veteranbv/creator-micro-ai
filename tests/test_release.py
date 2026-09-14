"""Test release orchestration without accessing any real keychain or service."""
import importlib.util
import json
import pathlib
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location("release", pathlib.Path(__file__).resolve().parents[1] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
REVISION = "a" * 40


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name).resolve()
        self.config = {"identity": "B" * 40, "team_id": "TESTTEAM01",
                       "keychain": str(self.root / "fixture.keychain-db"), "notary_profile": "fixture"}
        pathlib.Path(self.config["keychain"]).touch()
        self.calls = []
        self.failure = None
        self.status = "Accepted"
        self.dirty = False
        self.identity = True

    def command(self, label, *args, **kwargs):
        self.calls.append((label, args))
        if label == self.failure:
            raise RuntimeError("Synthetic failure")
        if label == "Check source revision":
            return REVISION
        if label == "Check source cleanliness":
            return " M fixture" if self.dirty else ""
        if label == "Read keychain search list":
            return '"/synthetic/login.keychain-db"'
        if label == "Check local signing identity":
            return self.config["identity"] + ' "Developer ID Application: Fixture"' if self.identity else ""
        if label == "Export exact source revision":
            with zipfile.ZipFile(args[-2].removeprefix("--output="), "w") as archive:
                archive.writestr("fixture", "synthetic source")
        if label == "Build both Mac architectures":
            app = pathlib.Path(kwargs["cwd"]) / "build/Creator Micro AI.app/Contents"
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": release.BUNDLE_ID,
                                                           "CFBundleShortVersionString": "0.1.0"}))
        if label in {"Package notarization submission", "Package stapled app"}:
            pathlib.Path(args[-1]).write_bytes(b"synthetic archive")
        if label == "Submit to Apple notarization":
            return json.dumps({"status": self.status})
        return ""

    def execute(self):
        with patch.object(release, "ROOT", self.root), patch.object(release, "run", side_effect=self.command):
            release.release(self.config, REVISION)

    def test_release_contains_only_final_archive_and_checksum(self):
        self.execute()
        directory = next((self.root / "build/releases").iterdir())
        self.assertEqual(sorted(file.suffix for file in directory.iterdir()), ["", ".zip"])
        self.assertIn(".zip", (directory / "SHA256SUMS").read_text())
        labels = [label for label, _ in self.calls]
        self.assertLess(labels.index("Staple notarization ticket"), labels.index("Package stapled app"))
        self.assertLess(labels.index("Extract final download"), labels.index("Validate delivered ticket"))
        signing = next(args for label, args in self.calls if label == "Sign using local keychain")
        self.assertIn("runtime", signing)
        self.assertIn("--timestamp", signing)
        self.assertIn("--keychain", signing)
        restore = next(args for label, args in self.calls if label == "Restore keychain search list")
        self.assertEqual(restore[-1], "/synthetic/login.keychain-db")
        self.assertFalse(any("export" in args or "unlock-keychain" in args for _, args in self.calls))

    def test_failures_never_leave_a_release_or_temporary_material(self):
        for label in ("Sign using local keychain", "Verify Developer ID and bundle identity",
                      "Submit to Apple notarization", "Staple notarization ticket",
                      "Extract final download", "Validate delivered ticket", "Check Gatekeeper"):
            with self.subTest(label=label):
                self.failure = label
                with self.assertRaises(RuntimeError):
                    self.execute()
                self.assertEqual(list((self.root / "build/releases").iterdir()), [])

    def test_rejected_notarization_stops_before_stapling(self):
        self.status = "Invalid"
        with self.assertRaisesRegex(RuntimeError, "did not accept"):
            self.execute()
        self.assertNotIn("Staple notarization ticket", [label for label, _ in self.calls])
        self.assertEqual(list((self.root / "build/releases").iterdir()), [])

    def test_signing_failure_restores_original_search_list(self):
        self.failure = "Sign using local keychain"
        with self.assertRaises(RuntimeError):
            self.execute()
        self.assertEqual(self.calls[-1], ("Restore keychain search list",
                         ("security", "list-keychains", "-d", "user", "-s", "/synthetic/login.keychain-db")))

    def test_interrupted_signing_restores_original_search_list(self):
        def interrupted(label, *args, **kwargs):
            if label == "Sign using local keychain":
                raise KeyboardInterrupt
            return self.command(label, *args, **kwargs)
        with patch.object(release, "run", side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):
                release.sign(self.root / "Creator Micro AI.app", self.config)
        self.assertEqual(self.calls[-1][0], "Restore keychain search list")

    def test_dirty_source_and_missing_identity_stop_before_signing(self):
        for field in ("dirty", "identity"):
            with self.subTest(field=field):
                self.dirty = field == "dirty"
                self.identity = field != "identity"
                with self.assertRaises(RuntimeError):
                    self.execute()
                self.assertNotIn("Sign using local keychain", [label for label, _ in self.calls])

    def test_existing_release_is_preserved(self):
        self.execute()
        self.calls.clear()
        with self.assertRaisesRegex(RuntimeError, "not be overwritten"):
            self.execute()
        self.assertNotIn("Sign using local keychain", [label for label, _ in self.calls])
        self.assertEqual(len(list((self.root / "build/releases").iterdir())), 1)

    def test_configuration_rejects_passwords_and_invalid_identities(self):
        path = self.root / "config.json"
        for update in ({"password": "synthetic"}, {"identity": "-"}, {"team_id": "bad"}):
            path.write_text(json.dumps({**self.config, **update}))
            with self.assertRaises(RuntimeError):
                release.settings(path)
        path.write_text(json.dumps(self.config))
        self.assertEqual(release.settings(path), self.config)

    def test_command_failure_does_not_disclose_raw_diagnostics(self):
        with patch.object(release.subprocess, "run", side_effect=subprocess.CalledProcessError(
                1, ["fixture"], stderr="synthetic sensitive diagnostic")):
            with self.assertRaisesRegex(RuntimeError, "Check fixture failed") as caught:
                release.run("Check fixture", "fixture")
        self.assertNotIn("sensitive", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
