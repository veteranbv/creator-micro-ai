"""Test release orchestration without accessing any real keychain or service."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import plistlib
import py_compile
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
        (self.root / "fixture").write_text("synthetic source")
        self.config = {"identity": "B" * 40, "team_id": "TESTTEAM01",
                       "keychain": str(self.root / "fixture.keychain-db"), "notary_profile": "fixture",
                       "node": str(pathlib.Path(sys.executable).resolve())}
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
        if label == "Check complete source history":
            return "false"
        if label == "Check configured Node version":
            return "v22.0.0"
        if label == "Check source cleanliness":
            return " M fixture" if self.dirty else ""
        if label == "Read keychain search list":
            return '"/synthetic/login.keychain-db"'
        if label == "Check local signing identity":
            return self.config["identity"] + ' "Developer ID Application: Fixture"' if self.identity else ""
        if label == "Export exact source revision":
            with zipfile.ZipFile(args[-2].removeprefix("--output="), "w") as archive:
                archive.writestr("fixture", "synthetic source")
        if label == "Create isolated test checkout":
            source = pathlib.Path(args[-1])
            source.mkdir()
            (source / "fixture").write_text("synthetic source")
        if label in {"Read reviewed source tree", "Read checkout source tree"}:
            data = b"synthetic source"
            oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
            return f"100644 blob {oid}\tfixture\0"
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
        system_tools = {"git", "codesign", "security", "xcrun", "ditto", "lipo", "spctl", "jq", "bash"}
        for label, args in self.calls:
            tool = pathlib.Path(args[0]).name
            if tool in system_tools:
                expected = ("/bin/" if tool == "bash" else "/usr/sbin/" if tool == "spctl" else "/usr/bin/") + tool
                self.assertEqual(args[0], expected, label)
                if tool == "git":
                    self.assertEqual(args[1], "--no-replace-objects", label)
        tests = next(args for label, args in self.calls if label == "Run full test suite")
        self.assertEqual(tests, ("/bin/bash", "scripts/test.sh", self.config["node"], sys.executable, "/usr/bin/jq"))

    def test_ignored_bytecode_cannot_replace_reviewed_tests(self):
        for directory in ("tests", ".github/scripts"):
            with self.subTest(directory=directory), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                environment = {"PATH": os.environ["PATH"], "HOME": str(root),
                               "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
                def git(*args):
                    return subprocess.check_output(["/usr/bin/git", *args], cwd=root,
                                                   env=environment, stderr=subprocess.DEVNULL)
                git("init", "-b", "main")
                git("config", "user.name", "Fixture")
                git("config", "user.email", "123+fixture@users.noreply.github.com")
                (root / ".gitignore").write_text("__pycache__/\n*.pyc\n")
                (root / "scripts").mkdir()
                (root / "scripts/test.sh").write_text(
                    'set -e\n"$2" -m unittest discover -s ' + directory + " -p 'test_*.py'\n")
                test = root / directory / "test_fixture.py"
                test.parent.mkdir(parents=True, exist_ok=True)
                passing = "import unittest\nclass Fixture(unittest.TestCase):\n def test_source(self): self.assertTrue(True )\n"
                failing = passing.replace("True ", "False")
                test.write_text(passing)
                os.utime(test, (1600000000, 1600000000))
                cache = pathlib.Path(py_compile.compile(str(test), doraise=True))
                test.write_text(failing)
                os.utime(test, (1600000000, 1600000000))
                original_cache = cache.read_bytes()
                git("add", ".")
                git("-c", "commit.gpgsign=false", "commit", "-m", "Reviewed failing fixture")
                revision = git("rev-parse", "HEAD").decode().strip()
                self.assertEqual(git("status", "--porcelain"), b"")
                with patch.dict(os.environ, environment, clear=True), patch.object(release, "ROOT", root):
                    release.clean_revision(revision)
                    # Reproduce the old behavior: ignored bytecode makes failing source pass.
                    release.run("Reproduce cached tests", "/bin/bash", "scripts/test.sh", "unused", sys.executable, cwd=root)
                    with self.assertRaisesRegex(RuntimeError, "Run full test suite failed"):
                        release.test_reviewed_source(self.config, revision)
                self.assertEqual(cache.read_bytes(), original_cache)

    def test_isolated_publication_scan_includes_custom_ref_history(self):
        root = self.root / "checkout"
        root.mkdir()
        environment = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        def git(*args):
            return subprocess.check_output(["/usr/bin/git", *args], cwd=root,
                                           env=environment, stderr=subprocess.DEVNULL)
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "123+fixture@users.noreply.github.com")
        (root / "scripts").mkdir()
        for name in ("publication_check.py", "privacy_check.py", "artwork_metadata.py", "public-tlds.txt"):
            (root / "scripts" / name).write_bytes((release.ROOT / "scripts" / name).read_bytes())
        (root / "scripts/test.sh").write_text('set -e\n"$2" scripts/publication_check.py --all-history\n')
        (root / ".gitignore").write_text("__pycache__/\n")
        git("add", ".")
        git("-c", "commit.gpgsign=false", "commit", "-m", "Reviewed fixture")
        revision = git("rev-parse", "HEAD").decode().strip()
        tree = git("rev-parse", "HEAD^{tree}").decode().strip()
        # Only the custom ref reaches this synthetic non-no-reply identity.
        archived = git("-c", "user.email=fixture@example.test", "-c", "commit.gpgsign=false",
                       "commit-tree", tree, "-m", "Archived fixture").decode().strip()
        with patch.dict(os.environ, environment, clear=True), patch.object(release, "ROOT", root):
            release.test_reviewed_source(self.config, revision)
            for reference in ("refs/archive/fixture", "refs/remotes/retired/fixture", "refs/remotes/origin/main"):
                with self.subTest(reference=reference):
                    git("update-ref", reference, archived)
                    if reference == "refs/remotes/origin/main":
                        git("symbolic-ref", "refs/remotes/origin/HEAD", reference)
                        git("branch", "-m", "topic")
                    self.assertEqual(len(git("rev-list", "--all").splitlines()), 2)
                    with self.assertRaisesRegex(RuntimeError, "Run full test suite failed"):
                        release.test_reviewed_source(self.config, revision)
                    for setting in ("uploadpack.hideRefs", "transfer.hideRefs"):
                        with self.subTest(setting=setting):
                            git("config", setting, reference)
                            with self.assertRaisesRegex(RuntimeError, "publication refs"):
                                release.test_reviewed_source(self.config, revision)
                            self.assertEqual(git("config", "--get", setting).decode().strip(), reference)
                            git("config", "--unset", setting)
                    self.assertEqual(git("rev-parse", reference).decode().strip(), archived)
                    git("update-ref", "-d", reference)

    def test_shallow_checkout_stops_before_credentials(self):
        environment = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        def git(*args):
            return subprocess.check_output(["/usr/bin/git", *args], cwd=self.root,
                                           env=environment, stderr=subprocess.DEVNULL)
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "123+fixture@users.noreply.github.com")
        git("add", "fixture")
        git("-c", "commit.gpgsign=false", "commit", "-m", "Initial fixture")
        git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Reviewed fixture")
        revision = git("rev-parse", "HEAD").decode().strip()
        with tempfile.TemporaryDirectory() as temporary:
            checkout = pathlib.Path(temporary) / "shallow"
            git("clone", "--no-local", "--depth=1", "--template=", str(self.root), str(checkout))
            self.assertEqual(git("-C", str(checkout), "rev-parse", "--is-shallow-repository").strip(), b"true")
            actual_run = release.run
            def checked_run(label, *args, **kwargs):
                if args[0] != "/usr/bin/git":
                    self.fail("Shallow checkout reached credential or build tools")
                return actual_run(label, *args, **kwargs)
            with patch.dict(os.environ, environment, clear=True), patch.object(release, "ROOT", checkout), \
                    patch.object(release, "run", side_effect=checked_run):
                with self.assertRaisesRegex(RuntimeError, "complete Git history"):
                    release.release(self.config, revision)

    def test_missing_or_relative_node_path_is_rejected(self):
        path = self.root / "config.json"
        for node in ("node", str(self.root / "missing"), str(self.root)):
            path.write_text(json.dumps({**self.config, "node": node}))
            with self.subTest(node=node), self.assertRaisesRegex(RuntimeError, "absolute executable"):
                release.settings(path)

    def test_old_node_version_stops_before_credentials(self):
        def command(label, *args, **kwargs):
            if label == "Check configured Node version":
                return "v20.0.0"
            return self.command(label, *args, **kwargs)
        with patch.object(release, "ROOT", self.root), patch.object(release, "run", side_effect=command), self.assertRaisesRegex(RuntimeError, "22 or newer"):
            release.release(self.config, REVISION)
        self.assertNotIn("Check local signing identity", [label for label, _ in self.calls])

    def test_hidden_worktree_changes_stop_before_credentials(self):
        checkout = self.root / "checkout"
        checkout.mkdir()
        environment = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        def git(*args):
            return subprocess.check_output(["/usr/bin/git", *args], cwd=checkout,
                                           env=environment, stderr=subprocess.DEVNULL)
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "123+fixture@users.noreply.github.com")
        git("config", "core.autocrlf", "true")
        source = checkout / "fixture"
        source.write_bytes(b"reviewed source\n")
        git("add", "fixture")
        git("-c", "commit.gpgsign=false", "commit", "-m", "Reviewed fixture")
        reviewed = git("rev-parse", "HEAD").decode().strip()
        actual_run = release.run
        def checked_run(label, *args, **kwargs):
            if args[0] != "/usr/bin/git":
                self.fail("Hidden source changes reached credential or build tools")
            kwargs.setdefault("cwd", checkout)
            return actual_run(label, *args, **kwargs)
        for flag in ("skip-worktree", "assume-unchanged"):
            with self.subTest(flag=flag):
                git("update-index", "--" + flag, "fixture")
                source.write_bytes(b"unreviewed source\n")
                self.assertEqual(git("status", "--porcelain"), b"")
                with patch.dict(os.environ, environment, clear=True), patch.object(release, "ROOT", checkout), \
                        patch.object(release, "run", side_effect=checked_run):
                    with self.assertRaisesRegex(RuntimeError, "index flags"):
                        release.release(self.config, reviewed)
                source.write_bytes(b"reviewed source\n")
                git("update-index", "--no-" + flag, "fixture")
        # Clean filters can also make status clean while checkout bytes differ.
        source.write_bytes(b"reviewed source\r\n")
        git("add", "fixture")
        self.assertEqual(git("status", "--porcelain"), b"")
        with patch.dict(os.environ, environment, clear=True), patch.object(release, "ROOT", checkout), \
                patch.object(release, "run", side_effect=checked_run):
            with self.assertRaisesRegex(RuntimeError, "checkout bytes"):
                release.release(self.config, reviewed)

    def test_test_time_source_changes_stop_before_export(self):
        def command(label, *args, **kwargs):
            if label == "Run full test suite":
                (self.root / "fixture").write_bytes(b"changed during tests")
            return self.command(label, *args, **kwargs)
        with patch.object(release, "ROOT", self.root), patch.object(release, "run", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "checkout bytes"):
                release.release(self.config, REVISION)
        self.assertNotIn("Export exact source revision", [label for label, _ in self.calls])

    def test_isolated_test_source_changes_stop_before_export(self):
        def command(label, *args, **kwargs):
            if label == "Run full test suite":
                (pathlib.Path(kwargs["cwd"]) / "fixture").write_bytes(b"changed during tests")
            return self.command(label, *args, **kwargs)
        with patch.object(release, "ROOT", self.root), patch.object(release, "run", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "checkout bytes"):
                release.release(self.config, REVISION)
        self.assertNotIn("Export exact source revision", [label for label, _ in self.calls])

    def test_real_replacement_refs_stop_release_before_credentials(self):
        checkout = self.root / "checkout"
        checkout.mkdir()
        environment = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        def git(*args):
            return subprocess.check_output(["/usr/bin/git", *args], cwd=checkout, env=environment, stderr=subprocess.DEVNULL)
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "123+fixture@users.noreply.github.com")
        source = checkout / "fixture"
        source.write_text("reviewed source")
        git("add", "fixture")
        git("-c", "commit.gpgsign=false", "commit", "-m", "Reviewed fixture")
        reviewed = git("rev-parse", "HEAD").decode().strip()
        original_blob = git("rev-parse", "HEAD:fixture").decode().strip()
        source.write_text("replacement source")
        git("add", "fixture")
        git("-c", "commit.gpgsign=false", "commit", "-m", "Replacement fixture")
        replacement = git("rev-parse", "HEAD").decode().strip()
        replacement_blob = git("rev-parse", "HEAD:fixture").decode().strip()
        git("update-ref", "refs/heads/main", reviewed)
        actual_run = release.run
        for original, substitute in ((reviewed, replacement), (original_blob, replacement_blob)):
            with self.subTest(object=original):
                git("replace", original, substitute)
                self.assertEqual(git("rev-parse", "HEAD").decode().strip(), reviewed)
                if original == reviewed:
                    self.assertEqual(git("status", "--porcelain"), b"")
                with zipfile.ZipFile(io.BytesIO(git("archive", "--format=zip", reviewed))) as handle:
                    self.assertEqual(handle.read("fixture"), b"replacement source")
                with zipfile.ZipFile(io.BytesIO(git("--no-replace-objects", "archive", "--format=zip", reviewed))) as handle:
                    self.assertEqual(handle.read("fixture"), b"reviewed source")
                calls = []
                def checked_run(label, *args, **kwargs):
                    calls.append(label)
                    if args[0] != "/usr/bin/git":
                        self.fail("Replacement refs reached credential or build tools")
                    kwargs.setdefault("cwd", checkout)
                    return actual_run(label, *args, **kwargs)
                with patch.dict(os.environ, environment, clear=True), patch.object(release, "ROOT", checkout), patch.object(release, "run", side_effect=checked_run):
                    with self.assertRaisesRegex(RuntimeError, "replacement"):
                        release.release(self.config, reviewed)
                self.assertNotIn("Check local signing identity", calls)
                git("replace", "-d", original)

    def test_release_contains_only_final_archive_and_checksum(self):
        self.execute()
        directory = next((self.root / "build/releases").iterdir())
        self.assertEqual(sorted(file.suffix for file in directory.iterdir()), ["", ".zip"])
        self.assertIn(".zip", (directory / "SHA256SUMS").read_text())
        labels = [label for label, _ in self.calls]
        self.assertLess(labels.index("Staple notarization ticket"), labels.index("Package stapled app"))
        self.assertLess(labels.index("Extract final download"), labels.index("Validate delivered ticket"))
        architecture_checks = [args for _, args in self.calls if args[0] == "/usr/bin/lipo"]
        self.assertEqual(len(architecture_checks), 2)
        for args, architecture in zip(architecture_checks, ("arm64", "x86_64")):
            self.assertEqual(len(args), 4)
            self.assertTrue(args[1].endswith("verification/Creator Micro AI.app/Contents/MacOS/CreatorMicroAI"))
            self.assertEqual(args[2:], ("-verify_arch", architecture))
        self.assertEqual(architecture_checks[0][1], architecture_checks[1][1])
        signing = next(args for label, args in self.calls if label == "Sign using local keychain")
        self.assertIn("runtime", signing)
        self.assertIn("--timestamp", signing)
        self.assertIn("--keychain", signing)
        restore = next(args for label, args in self.calls if label == "Restore keychain search list")
        self.assertEqual(restore[-1], "/synthetic/login.keychain-db")
        self.assertFalse(any("export" in args or "unlock-keychain" in args for _, args in self.calls))

    def test_real_git_attributes_cannot_change_release_source(self):
        checkout = self.root / "checkout"
        checkout.mkdir()
        environment = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        def git(*args, cwd=checkout):
            return subprocess.check_output(["/usr/bin/git", *args], cwd=cwd,
                                           env=environment, stderr=subprocess.DEVNULL)
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "123+fixture@users.noreply.github.com")
        original = b"reviewed $Format:%H$\n"
        (checkout / "fixture").write_bytes(original)
        (checkout / "nested").mkdir()
        (checkout / "nested/binary fixture").write_bytes(b"\0\xff\r\n")
        git("add", "fixture", "nested")
        git("-c", "commit.gpgsign=false", "commit", "-m", "Reviewed fixture")
        reviewed = git("rev-parse", "HEAD").decode().strip()
        def checked_run(label, *args, **kwargs):
            if args[0] == "/usr/bin/git":
                self.calls.append((label, args))
                return git(*args[1:], cwd=kwargs.get("cwd", checkout)).decode()
            return self.command(label, *args, **kwargs)
        for location in ("local", "configured"):
            attributes = checkout / ".git/info/attributes" if location == "local" else self.root / "attributes"
            git("config", "core.attributesFile", str(attributes))
            for attribute in ("export-ignore", "export-subst"):
                with self.subTest(location=location, attribute=attribute):
                    output_root = checkout
                    attributes.write_text(f"fixture {attribute}\n")
                    self.assertEqual(git("status", "--porcelain"), b"")
                    with zipfile.ZipFile(io.BytesIO(git("archive", "--format=zip", reviewed))) as handle:
                        if attribute == "export-ignore":
                            self.assertNotIn("fixture", handle.namelist())
                        else:
                            self.assertNotEqual(handle.read("fixture"), original)
                    self.calls.clear()
                    with patch.object(release, "ROOT", output_root), patch.object(release, "run", side_effect=checked_run):
                        with self.assertRaisesRegex(RuntimeError, "reviewed tree"):
                            release.release(self.config, reviewed)
                    self.assertNotIn("Build both Mac architectures", [label for label, _ in self.calls])
                    self.assertNotIn("Sign using local keychain", [label for label, _ in self.calls])
                    self.assertEqual(list((output_root / "build/releases").iterdir()), [])
            attributes.unlink()
        archive = self.root / "source.zip"
        archive.write_bytes(git("archive", "--format=zip", reviewed))
        source = self.root / "extracted"
        with patch.object(release, "run", side_effect=checked_run):
            release.extract_reviewed_source(archive, source, reviewed)
        self.assertEqual((source / "fixture").read_bytes(), original)
        self.assertEqual((source / "nested/binary fixture").read_bytes(), b"\0\xff\r\n")

    def test_source_archive_rejects_changed_paths_and_bytes_before_extraction(self):
        original = ("fixture", b"synthetic source")
        for entries in ([], [("fixture", b"changed")], [original, ("extra", b"extra")],
                        [original, original], [("../escape", b"extra")], [original, ("extra/", b"")]):
            with self.subTest(entries=entries):
                archive = self.root / "source.zip"
                source = self.root / "extracted"
                with contextlib.redirect_stderr(io.StringIO()), zipfile.ZipFile(archive, "w") as handle:
                    for name, data in entries:
                        handle.writestr(name, data)
                with patch.object(release, "run", side_effect=self.command):
                    with self.assertRaisesRegex(RuntimeError, "reviewed tree"):
                        release.extract_reviewed_source(archive, source, REVISION)
                self.assertFalse(source.exists())

    def test_failures_never_leave_a_release_or_temporary_material(self):
        for label in ("Sign using local keychain", "Verify Developer ID and bundle identity",
                      "Submit to Apple notarization", "Staple notarization ticket",
                      "Extract final download", "Verify delivered arm64 architecture",
                      "Verify delivered x86_64 architecture", "Validate delivered ticket", "Check Gatekeeper"):
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

    def test_xcode_overrides_never_redirect_release_build_or_signing_tools(self):
        environment = {"PATH": "/synthetic/tools", "HOME": "/synthetic/home",
                       "DEVELOPER_DIR": "/synthetic/developer", "SDKROOT": "/synthetic/sdk",
                       "TOOLCHAINS": "synthetic", "CREATOR_SIGNING_PASSWORD": "synthetic"}
        commands = (("/usr/bin/xcrun", "notarytool", "history"),
                    ("/usr/bin/xcrun", "stapler", "validate", "fixture"),
                    ("/usr/bin/codesign", "--verify", "fixture"),
                    ("/bin/bash", "scripts/test.sh"), ("/bin/bash", "scripts/build.sh", "--universal"))
        for arguments in commands:
            with self.subTest(arguments=arguments), patch.dict(os.environ, environment, clear=True), patch.object(release.subprocess, "Popen") as command:
                process = command.return_value.__enter__.return_value
                process.communicate.return_value = ("", "")
                process.returncode = 0
                release.run("Synthetic tool", *arguments)
                allowed = ("PATH", "HOME")
                self.assertEqual(command.call_args.kwargs["env"], {key: environment[key] for key in allowed})

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
                        state = subprocess.run(["/bin/ps", "-o", "stat=", "-p", pid], capture_output=True, text=True).stdout.strip()
                        if not state or state.startswith("Z"):
                            break
                        if time.monotonic() >= deadline:
                            self.fail("Synthetic descendant survived command cleanup")
                        time.sleep(0.02)


if __name__ == "__main__":
    unittest.main()
