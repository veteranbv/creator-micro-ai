"""Synthetic publication fixtures contain no actual private identifiers."""
import pathlib
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from publication_check import content_findings, identity_allowed
import publication_check


class PublicationTests(unittest.TestCase):
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

    def test_untracked_source_is_checked_before_staging(self):
        with tempfile.TemporaryDirectory(prefix="publication-new-test-") as directory:
            root = pathlib.Path(directory)
            (root / "new.swift").write_text("private-project" + ".ai")
            def git(*args):
                if args[0] == "for-each-ref" or args[0] == "rev-list":
                    return b""
                self.assertEqual(args, ("ls-files", "--cached", "--others", "--exclude-standard", "-z"))
                return b"new.swift\0"
            with mock.patch.object(publication_check, "ROOT", root), mock.patch.object(publication_check, "git", git), mock.patch.object(sys, "argv", ["check"]), contextlib.redirect_stdout(io.StringIO()):
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
            git("tag", "-a", "fixture", "-m", "private-project" + ".ai")
            with mock.patch.object(publication_check, "ROOT", root):
                self.assertTrue(publication_check.tag_findings())
            git("config", "user.email", "person@example.test")
            git("tag", "-a", "identity-fixture", "-m", "Public fixture")
            with mock.patch.object(publication_check, "ROOT", root):
                self.assertIn("non-private tagger email", [issue for _,issue in publication_check.tag_findings()])


if __name__ == "__main__":
    unittest.main()
