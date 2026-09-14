"""Test release orchestration without accessing any real keychain or service."""
import importlib.util
import json
import os
import pathlib
import plistlib
import subprocess
import signal
import sys
import time
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

    def execute(self, password=None):
        with patch.object(release, "ROOT", self.root), patch.object(release, "run", side_effect=self.command):
            release.release(self.config, REVISION, password)

    def test_keychain_is_unlocked_only_for_signing(self):
        self.execute("synthetic")
        labels = [label for label, _ in self.calls]
        unlock = labels.index("Unlock dedicated signing keychain")
        lock = labels.index("Lock dedicated signing keychain")
        self.assertEqual(labels[unlock:lock + 1], ["Unlock dedicated signing keychain",
                         "Read keychain search list", "Enable signing keychain temporarily",
                         "Sign using local keychain", "Restore keychain search list", "Lock dedicated signing keychain"])
        self.assertLess(labels.index("Build both Mac architectures"), unlock)
        self.assertLess(lock, labels.index("Submit to Apple notarization"))

    def test_sensitive_release_tools_use_fixed_system_paths(self):
        with patch.dict(os.environ, {"PATH": "/synthetic/shadow-tools"}):
            self.execute("synthetic")
        system_tools = {"git", "codesign", "security", "xcrun", "ditto", "lipo", "spctl"}
        for label, args in self.calls:
            tool = pathlib.Path(args[0]).name
            if tool in system_tools:
                expected = ("/usr/sbin/" if tool == "spctl" else "/usr/bin/") + tool
                self.assertEqual(args[0], expected, label)

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
                         ("/usr/bin/security", "list-keychains", "-d", "user", "-s", "/synthetic/login.keychain-db")))

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
        with patch.object(release.subprocess, "Popen", side_effect=subprocess.CalledProcessError(
                1, ["fixture"], stderr="synthetic sensitive diagnostic")):
            with self.assertRaisesRegex(RuntimeError, "Check fixture failed") as caught:
                release.run("Check fixture", "fixture")
        self.assertNotIn("sensitive", str(caught.exception))

    def test_secret_manager_unlock_uses_stdin_and_relocks_after_failure_or_interrupt(self):
        for failure in (None, RuntimeError("Synthetic failure"), KeyboardInterrupt()):
            with self.subTest(failure=type(failure).__name__), patch.object(release, "run") as command:
                def exercise():
                    with release.unlocked_keychain(self.config, "synthetic #!$'\\\" password"):
                        if failure:
                            raise failure
                if failure:
                    with self.assertRaises(type(failure)):
                        exercise()
                else:
                    exercise()
                self.assertEqual(command.call_count, 2)
                unlock, lock = command.call_args_list
                self.assertEqual(unlock.args[1:3], ("/usr/bin/security", "unlock-keychain"))
                self.assertEqual(unlock.kwargs["input"], "synthetic #!$'\\\" password\n")
                self.assertNotIn("-p", unlock.args)
                self.assertEqual(lock.args[2], "lock-keychain")

    def test_invalid_or_failed_unlock_never_starts_release(self):
        for password in ("", "line\nbreak", "line\rbreak", "null\0byte", "a" * 129, "é" * 65):
            with patch.object(release, "run") as command, self.assertRaises(RuntimeError):
                with release.unlocked_keychain(self.config, password):
                    self.fail("Invalid password entered release")
            command.assert_not_called()
        with patch.object(release, "run", side_effect=RuntimeError("Unlock failed")) as command:
            with self.assertRaises(RuntimeError):
                with release.unlocked_keychain(self.config, "synthetic"):
                    self.fail("Failed unlock entered release")
            self.assertEqual(command.call_count, 2)
            self.assertEqual(command.call_args.args[2], "lock-keychain")

    def test_manual_unlock_mode_does_not_change_keychain_lock_state(self):
        with patch.object(release, "run") as command:
            with release.unlocked_keychain(self.config, None):
                pass
        command.assert_not_called()

    def test_child_tools_receive_only_environment_allowlist(self):
        environment = {"PATH": "/synthetic/tools", "HOME": "/synthetic/home", "TMPDIR": "/synthetic/tmp",
                       "CREATOR_SIGNING_PASSWORD": "synthetic", "OP_SERVICE_ACCOUNT_TOKEN": "synthetic",
                       "UNRELATED_SECRET": "synthetic"}
        with patch.dict(os.environ, environment, clear=True), patch.object(release.subprocess, "Popen") as command:
            process = command.return_value.__enter__.return_value
            process.communicate.return_value = ("", "")
            process.returncode = 0
            release.run("Synthetic unlock", "/usr/bin/security", "unlock-keychain", "fixture", input="synthetic\n")
            self.assertEqual(command.call_args.kwargs["env"], {key: environment[key] for key in ("PATH", "HOME", "TMPDIR")})
            self.assertTrue(command.call_args.kwargs["start_new_session"])
            self.assertEqual(process.communicate.call_args.kwargs["input"], "synthetic\n")

    def test_real_cancellation_and_timeout_stop_command_descendants(self):
        def interrupted(signum, frame):
            raise KeyboardInterrupt
        original_handler = signal.signal(signal.SIGTERM, interrupted)
        self.addCleanup(signal.signal, signal.SIGTERM, original_handler)
        grandchild = "import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text(str(__import__('os').getpid())); time.sleep(60)"
        child = ("import os,pathlib,signal,subprocess,sys,time; "
                 "root=pathlib.Path(sys.argv[1]); "
                 "subprocess.Popen([sys.executable,'-c',sys.argv[2],str(root/'grandchild')]); "
                 "(root/'child').write_text(str(os.getpid())); "
                 "\nwhile not (root/'grandchild').exists(): time.sleep(0.01)\n"
                 "if sys.argv[3]=='interrupt': os.kill(os.getppid(),signal.SIGTERM)\n"
                 "time.sleep(60)")
        for mode in ("interrupt", "timeout"):
            with self.subTest(mode=mode):
                directory = self.root / mode
                directory.mkdir()
                exception = KeyboardInterrupt if mode == "interrupt" else RuntimeError
                with self.assertRaises(exception):
                    release.run("Synthetic cancellation", sys.executable, "-c", child,
                                str(directory), grandchild, mode, input="synthetic\n", timeout=3)
                for name in ("child", "grandchild"):
                    pid = (directory / name).read_text()
                    deadline = time.monotonic() + 5
                    while True:
                        state = subprocess.run(["ps", "-o", "stat=", "-p", pid], capture_output=True, text=True).stdout.strip()
                        if not state or state.startswith("Z"):
                            break
                        if time.monotonic() >= deadline:
                            self.fail("Synthetic descendant survived command cleanup")
                        time.sleep(0.02)


if __name__ == "__main__":
    unittest.main()
