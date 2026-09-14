"""Synthetic publication fixtures contain no actual private identifiers."""
import pathlib
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
import struct
import zlib
import zipfile
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from publication_check import content_findings, identity_allowed
import publication_check
import privacy_check


class PublicationTests(unittest.TestCase):
    def test_staged_archive_is_checked_when_worktree_is_clean_or_missing(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("private/.env", "SYNTHETIC_CREDENTIAL=fixture")
        with tempfile.TemporaryDirectory(prefix="publication-index-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, env=env, stderr=subprocess.DEVNULL)
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Clean fixture")
            file = root / "renamed.bin"
            file.write_bytes(b"#!/bin/sh\nexit 0\n" + archive.getvalue())
            git("add", "renamed.bin")
            file.write_text("Clean working copy")
            for missing in (False, True):
                if missing:
                    file.unlink()
                for checker in (privacy_check, publication_check):
                    with self.subTest(missing=missing, checker=checker.__name__):
                        output = io.StringIO()
                        with mock.patch.object(checker, "ROOT", root), mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(output):
                            self.assertEqual(checker.main(), 1)
                        self.assertIn("archive artifact", output.getvalue())

    def test_network_authorities_never_use_filename_exemptions(self):
        for host in ("buildserver", "localhost", "[fd00::1]", "192.0.2.1"):
            for prefix in ("ssh://", "tcp://", "custom+transport://", "//"):
                self.assertTrue(content_findings("README.md", (prefix + host + "/private").encode()))
        self.assertTrue(content_findings("README.md", b"op://" + b"private-vault/item/password"))
        for stem, suffix in (("source", "zip"), ("submission", "zip"), ("release", "py"), ("README", "md")):
            host = stem + "." + suffix
            for prefix in ("ftp://", "ssh://", "tcp://", "custom+transport://", "//"):
                for authority in (host, "user@" + host + ":443"):
                    for name in ("README.md", "fixture.py"):
                        with self.subTest(prefix=prefix, authority=authority, name=name):
                            self.assertTrue(content_findings(name, ('endpoint = "' + prefix + authority + '/private"').encode()))
        self.assertFalse(content_findings("README.md", b"[Project](//github.com/example)"))
        self.assertFalse(content_findings("README.md", b"op://YOUR_VAULT/YOUR_ITEM/password"))
        self.assertFalse(content_findings("Info.plist", b'PUBLIC "-//Apple//DTD PLIST 1.0//EN"'))

    def test_index_read_failure_blocks_both_checks_without_raw_diagnostics(self):
        with tempfile.TemporaryDirectory(prefix="publication-index-failure-test-") as directory:
            for checker in (privacy_check, publication_check):
                output = io.StringIO()
                with mock.patch.object(checker, "ROOT", pathlib.Path(directory)), mock.patch.object(checker, "staged_blobs", side_effect=ValueError("SYNTHETIC_PRIVATE_DETAIL")), mock.patch.object(publication_check, "git", return_value=b""), mock.patch.object(sys, "argv", ["check"]), contextlib.redirect_stdout(output):
                    self.assertEqual(checker.main(), 1)
                self.assertIn("index inspection failed", output.getvalue())
                self.assertNotIn("SYNTHETIC_PRIVATE_DETAIL", output.getvalue())

    def test_index_rejects_special_modes_conflicts_and_unreadable_blobs(self):
        for mode, stage in (("120000", "0"), ("160000", "0"), ("100644", "1")):
            entry = (mode + " " + "a" * 40 + " " + stage + "\tfixture.bin\0").encode()
            with mock.patch.object(subprocess, "check_output", return_value=entry), self.assertRaises(ValueError):
                list(privacy_check.staged_blobs(pathlib.Path(".")))
        entry = ("100644 " + "a" * 40 + " 0\tfixture.bin\0").encode()
        failure = subprocess.CalledProcessError(1, ["git"], stderr=b"SYNTHETIC_PRIVATE_DETAIL")
        with mock.patch.object(subprocess, "check_output", side_effect=[entry, failure]), self.assertRaises(ValueError):
            list(privacy_check.staged_blobs(pathlib.Path(".")))

    def test_new_python_member_exemptions_require_member_access(self):
        for owner, attribute in (("release", "run"), ("download", "name"), ("self", "fail")):
            member = owner + "." + attribute
            self.assertFalse(content_findings("fixture.py", (member + "()").encode()))
            self.assertFalse(content_findings("fixture.py", ('label = "é"; ' + member + "()").encode()))
            for name in ("helper" + ".py", "tests/test_publication.py", "scripts/publication_check.py", "fixture.yaml"):
                for source in ('socket.connect(("' + member + '", 443))', '# ' + member,
                               'endpoint = "' + member + '"', 'endpoint = f"' + member + '"',
                               'endpoint = "https://' + member + '"'):
                    self.assertTrue(content_findings(name, source.encode()))
            self.assertTrue(content_findings("fixture.py", (member + "(").encode()))

    def test_archives_are_rejected_even_when_renamed_or_only_in_history(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("private/.env", "SYNTHETIC_CREDENTIAL=fixture")
        for name in ("source.zip", "submission.zip", "download" + ".ZIP", "renamed.bin", "tag-blob"):
            self.assertIn("archive artifact must not be published", content_findings(name, archive.getvalue()))
            self.assertIn("archive artifact must not be published", content_findings(name, b"#!/bin/sh\nexit 0\n" + archive.getvalue()))
        for name in ("source.zip", "submission.zip", "download" + ".ZIP"):
            self.assertIn("archive artifact must not be published", publication_check.path_findings(name))
        self.assertFalse(content_findings("fixture.py", b'archive = stage / "source.zip"; upload = stage / "submission.zip"'))
        with tempfile.TemporaryDirectory(prefix="publication-archive-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, env=env, stderr=subprocess.DEVNULL)
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            (root / "renamed.bin").write_bytes(b"#!/bin/sh\nexit 0\n" + archive.getvalue())
            git("add", "renamed.bin")
            with mock.patch.object(privacy_check, "ROOT", root), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(privacy_check.main(), 1)
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add archive fixture")
            git("rm", "renamed.bin")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Remove archive fixture")
            with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(publication_check.main(), 1)

    def test_new_filename_exemptions_require_path_syntax(self):
        for stem, suffix in (("release", "py"), ("releases", "md"), ("source", "zip"), ("submission", "zip")):
            filename = stem + "." + suffix
            self.assertFalse(content_findings("fixture.py", ('path = stage / "' + filename + '"').encode()))
            self.assertFalse(content_findings("README.md", ('[File](docs/' + filename + ')').encode()))
            for name in ("fixture.py", "README.md", "repository-path", "scripts/publication_check.py", "tests/test_publication.py"):
                for source in ('socket.connect(("' + filename + '", 443))', 'endpoint = "' + filename + '"',
                               '# ' + filename, 'endpoint = "https://' + filename + '"'):
                    self.assertTrue(content_findings(name, source.encode()))

    def test_signing_branch_source_references_are_not_hosts(self):
        for name in ("releases.md", "release.py", "source.zip", "submission.zip"):
            self.assertTrue(content_findings("README.md", name.encode()))
        for name in ("releases.md", "release.py"):
            self.assertFalse(publication_check.path_findings(name))
        for expression in ("release.run", "download.name", "self.fail"):
            self.assertFalse(content_findings("fixture.py", expression.encode()))
            self.assertTrue(content_findings("README.md", expression.encode()))
            self.assertTrue(content_findings("fixture.py", ("https://" + expression).encode()))

    def test_private_directory_paths_are_forbidden_even_for_opaque_files(self):
        for name in ("private/device-export.bin", "docs/PRIVATE/export.bin", "local/Private/blob.dat",
                     "build/export.bin", "BUILD/export.bin", "node_modules/export.bin", "__pycache__/blob.bin",
                     ".swift-module-cache/export.bin", ".DS_Store", "docs/.ds_store", "cache.pyc", "CACHE.PYC"):
            self.assertIn("private local artifact must not be published", content_findings(name, b"\x00\xff"))
            self.assertIn("private local artifact must not be published", publication_check.path_findings(name))

    def test_force_added_private_binary_fails_index_and_history_checks(self):
        with tempfile.TemporaryDirectory(prefix="publication-private-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, env=env, stderr=subprocess.DEVNULL)
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            (root / ".gitignore").write_text("private/\n")
            (root / "private").mkdir()
            file = root / "private/device-export.bin"
            file.write_bytes(b"\x00\xff")
            with mock.patch.object(privacy_check, "ROOT", root), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(privacy_check.main(), 0)
            git("add", "-f", "private/device-export.bin")
            # The index guard must reject the path even if its worktree file disappears.
            file.unlink()
            with mock.patch.object(privacy_check, "ROOT", root), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(privacy_check.main(), 1)
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add opaque fixture")
            git("rm", "--cached", "private/device-export.bin")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Remove opaque fixture")
            with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(publication_check.main(), 1)

    def test_backup_directories_are_private_even_with_ordinary_filenames(self):
        for name in ("backups/device-123/keymap.before.json", "docs/BACKUPS/keymap.json", "local/Backup Copy/profile.json"):
            self.assertIn("private local artifact must not be published", content_findings(name, b"{}"))

    def test_png_metadata_is_checked_regardless_of_suffix_case(self):
        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
        start = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        end = chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff")) + chunk(b"IEND", b"")
        for suffix in ("png", "PNG", "Png"):
            name = "docs/assets/device." + suffix
            self.assertFalse(content_findings(name, start + end))
            for kind in (b"tEXt", b"eXIf"):
                self.assertIn("artwork metadata requires sanitization",
                              content_findings(name, start + chunk(kind, b"Synthetic metadata") + end))

    def test_embedded_icon_metadata_is_checked_in_history_and_unnamed_blobs(self):
        from artwork_metadata import sanitized_icon
        def chunk(kind, payload=b""):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR") + chunk(b"eXIf", b"Synthetic metadata") + chunk(b"IEND")
        icon = b"icns" + struct.pack(">I", len(png) + 16) + b"ic07" + struct.pack(">I", len(png) + 8) + png
        for name in ("assets/AppIcon.icns", "assets/ICON.ICNS", "tag-blob"):
            self.assertIn("icon metadata requires sanitization", content_findings(name, icon))
            self.assertFalse(content_findings(name, sanitized_icon(icon)))
        self.assertIn("icon metadata requires sanitization", content_findings("icon.icns", icon[:-1]))
        with tempfile.TemporaryDirectory(prefix="publication-icon-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, env=env, stderr=subprocess.DEVNULL)
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            file = root / "icon.icns"
            file.write_bytes(icon)
            git("add", "icon.icns")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add synthetic icon")
            file.write_bytes(sanitized_icon(icon))
            git("add", "icon.icns")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Sanitize current icon")
            with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(publication_check.main(), 1)

    def test_credential_artifact_names_are_case_insensitive(self):
        for suffix in ("pem", "p12", "mobileprovision", "log", "har", "trace"):
            for variant in (suffix, suffix.upper(), suffix.title()):
                self.assertIn("private local artifact must not be published",
                              content_findings("client." + variant, b"\x00\xff"))
        for name in (".ENV", ".Env.local", ".ENVRC"):
            self.assertTrue(content_findings(name, b"Generic fixture"))

    def test_commit_display_names_are_scanned_and_redacted(self):
        for field in ("GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"):
            with self.subTest(field=field), tempfile.TemporaryDirectory(prefix="publication-identity-test-") as directory:
                root = pathlib.Path(directory)
                env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                       "GIT_AUTHOR_NAME": "Fixture", "GIT_COMMITTER_NAME": "Fixture",
                       "GIT_AUTHOR_EMAIL": "123+fixture@users.noreply.github.com",
                       "GIT_COMMITTER_EMAIL": "123+fixture@users.noreply.github.com"}
                env[field] = "private-project" + ".ai"
                subprocess.run(["git", "init", "-b", "main"], cwd=root, env=env, check=True, capture_output=True)
                subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Public fixture"],
                               cwd=root, env=env, check=True, capture_output=True)
                output = io.StringIO()
                with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(output):
                    self.assertEqual(publication_check.main(), 1)
                self.assertIn("unapproved domain", output.getvalue())
                self.assertNotIn(env[field], output.getvalue())

    def test_paths_are_checked_without_source_expression_exemptions(self):
        for name in ("docs/private-project" + ".ai.txt", "private-project" + ".com/notes.md", "source.name" + ".py", "private-project" + ".com.test.js"):
            self.assertTrue(publication_check.path_findings(name))
        for name in ("README.md", "helper/Sources/main.swift", "scripts/build.sh", "tests/profile.test.js"):
            self.assertFalse(publication_check.path_findings(name))

    def test_tree_tags_and_historical_paths_are_checked(self):
        with tempfile.TemporaryDirectory(prefix="publication-tree-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, env=env, stderr=subprocess.DEVNULL).decode().strip()
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            (root / "README.md").write_text("Public fixture")
            git("add", "README.md")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add fixture")
            private_name = "private-project" + ".ai.txt"
            (root / private_name).write_text("Public fixture")
            (root / "notes.md").write_text("private-project" + ".com")
            git("add", private_name, "notes.md")
            tree = git("write-tree")
            git("tag", "tree-fixture", tree)
            git("tag", "-a", "annotated-tree-fixture", tree, "-m", "Public fixture")
            # The tagged tree is never committed and no unsafe working file remains.
            git("restore", "--staged", private_name, "notes.md")
            (root / private_name).unlink()
            (root / "notes.md").unlink()
            with mock.patch.object(publication_check, "ROOT", root):
                findings = publication_check.tag_findings()
                self.assertTrue(any(name == private_name for name, _ in findings))
                self.assertTrue(any(name == "notes.md" for name, _ in findings))
                output = io.StringIO()
                with mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(output):
                    self.assertEqual(publication_check.main(), 1)
                self.assertNotIn(private_name, output.getvalue())
                self.assertIn("path-sha256:", output.getvalue())
            # A private path in commit history is checked even after its removal.
            (root / private_name).write_text("Public fixture")
            git("add", private_name)
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add path fixture")
            git("rm", private_name)
            git("-c", "commit.gpgsign=false", "commit", "-m", "Remove path fixture")
            with mock.patch.object(publication_check, "ROOT", root):
                findings = publication_check.tree_findings("HEAD~1", set())
                self.assertTrue(any(name == private_name for name, _ in findings))

    def test_unrelated_domain_is_rejected_even_without_url(self):
        self.assertTrue(content_findings("README.md", b"a-private-project" + b".com"))

    def test_public_suffixes_and_local_hosts_are_checked(self):
        for suffix in (b"ai", b"co", b"app", b"cloud", b"design", b"uk", b"local", b"internal", b"xn--p1ai"):
            with self.subTest(suffix=suffix):
                self.assertTrue(content_findings("README.md", b"private-project." + suffix))

    def test_urls_do_not_depend_on_suffix_or_source_exceptions(self):
        for host in (b"private-project.unknownsuffix", b"localhost", b"source.name", b"README.md"):
            self.assertTrue(content_findings("fixture.py", b"https://" + host))

    def test_source_exceptions_do_not_exempt_prose(self):
        self.assertFalse(content_findings("fixture.py", b"source.name"))
        self.assertTrue(content_findings("README.md", b"source.name"))

    def test_native_pipe_read_is_source_only(self):
        self.assertFalse(content_findings("fixture.swift", b"Darwin.read"))
        self.assertTrue(content_findings("README.md", b"Darwin.read"))
        self.assertTrue(content_findings("fixture.swift", b"https://" + b"Darwin.read"))
        self.assertFalse(content_findings("fixture.swift", b"reads.read"))
        self.assertTrue(content_findings("README.md", b"reads.read"))
        self.assertTrue(content_findings("fixture.swift", b"https://" + b"reads.read"))

    def test_untracked_source_is_checked_before_staging(self):
        with tempfile.TemporaryDirectory(prefix="publication-new-test-") as directory:
            root = pathlib.Path(directory)
            (root / "new.swift").write_text("private-project" + ".ai")
            def git(*args):
                if args[0] == "for-each-ref" or args[0] == "rev-list":
                    return b""
                self.assertEqual(args, ("ls-files", "--cached", "--others", "--exclude-standard", "-z"))
                return b"new.swift\0"
            with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(publication_check, "git", git), mock.patch.object(publication_check, "staged_blobs", return_value=iter(())), mock.patch.object(sys, "argv", ["check"]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(publication_check.main(), 1)

    def test_documented_file_references_are_not_hosts(self):
        self.assertFalse(content_findings("README.md", b"bash scripts/test.sh"))
        self.assertFalse(content_findings("README.md", b"[Setup](docs/setup.md)"))

    def test_contact_email_is_rejected(self):
        self.assertTrue(content_findings("README.md", b"person@" + b"mail.example" + b".com"))

    def test_project_links_are_allowed(self):
        self.assertFalse(content_findings("README.md", b"https://worklouder.cc/creator-micro-2"))
        self.assertFalse(content_findings("README.md", b"https://veteranbv.github.io/creator-micro-ai/"))

    def test_documentation_images_require_clean_metadata(self):
        self.assertIn("artwork metadata requires sanitization",
                      content_findings("docs/assets/device.png", b"invalid PNG fixture"))

    def test_synthetic_email_is_allowed_in_test_content(self):
        self.assertFalse(content_findings("tests/example.py", b"person@example.test"))

    def test_commit_email_must_be_private(self):
        self.assertFalse(identity_allowed("person@example.test"))
        self.assertFalse(identity_allowed(""))
        self.assertFalse(identity_allowed("person@users.noreply.github.com" + ".invalid"))

    def test_private_commit_identities_are_allowed(self):
        self.assertTrue(identity_allowed("123+contributor@users.noreply.github.com"))
        self.assertTrue(identity_allowed("noreply@github.com"))

    def test_existing_privacy_rules_apply_to_history(self):
        self.assertTrue(content_findings("notes.md", b"/Users/" + b"synthetic/Documents"))
        self.assertTrue(content_findings("helper/main.swift", b"NSPasteboard"))

    def test_clean_tip_cannot_hide_an_unapproved_domain_in_history(self):
        with tempfile.TemporaryDirectory(prefix="publication-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                subprocess.run(["git", *args], cwd=root, env=env, check=True, capture_output=True)
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            (root / "README.md").write_text("a-private-project" + ".com")
            git("add", "README.md")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add fixture")
            (root / "README.md").write_text("Generic public documentation")
            git("add", "README.md")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Clean fixture")
            output = io.StringIO()
            with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(output):
                self.assertEqual(publication_check.main(), 1)
            self.assertIn("unapproved domain", output.getvalue())
            self.assertNotIn("a-private-project", output.getvalue())

    def test_annotated_tags_are_checked(self):
        with tempfile.TemporaryDirectory(prefix="publication-tag-test-") as directory:
            root = pathlib.Path(directory)
            env = {"PATH": os.environ["PATH"], "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            def git(*args):
                subprocess.run(["git", *args], cwd=root, env=env, check=True, capture_output=True)
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "123+fixture@users.noreply.github.com")
            (root / "README.md").write_text("Public fixture")
            git("add", "README.md")
            git("-c", "commit.gpgsign=false", "commit", "-m", "Add fixture")
            git("tag", "-a", "clean-fixture", "-m", "Public fixture")
            with mock.patch.object(publication_check, "ROOT", root):
                self.assertFalse(publication_check.tag_findings())
            private_tag = "private-project" + ".ai"
            git("tag", private_tag)
            with mock.patch.object(publication_check, "ROOT", root):
                self.assertTrue(publication_check.tag_findings())
                output = io.StringIO()
                with mock.patch.object(sys, "argv", ["check", "--all-history"]), contextlib.redirect_stdout(output):
                    self.assertEqual(publication_check.main(), 1)
                self.assertNotIn(private_tag, output.getvalue())
            git("tag", "-d", private_tag)
            git("tag", "-a", "fixture", "-m", "private-project" + ".ai")
            with mock.patch.object(publication_check, "ROOT", root):
                self.assertTrue(publication_check.tag_findings())
            git("config", "user.email", "person@example.test")
            git("tag", "-a", "identity-fixture", "-m", "Public fixture")
            with mock.patch.object(publication_check, "ROOT", root):
                self.assertIn("non-private tagger email", [issue for _,issue in publication_check.tag_findings()])


if __name__ == "__main__":
    unittest.main()
