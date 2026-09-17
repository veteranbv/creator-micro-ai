"""Build and verify a local notarized release without exporting signing keys."""
import argparse
import contextlib
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUNDLE_ID = "community.creatormicroai.helper"


def run(label, *command, cwd=ROOT, timeout=1200, input=None):
    print(label, flush=True)
    # Preserve PATH, but invoke release tools and their build children explicitly.
    environment = {key: value for key, value in os.environ.items() if key in {
        "PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL",
        "MACOSX_DEPLOYMENT_TARGET",
    }}
    try:
        with subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                              text=True, env=environment, start_new_session=True) as child_process:
            try:
                stdout, _ = child_process.communicate(input=input, timeout=timeout)
            except BaseException:
                # Stop descendants too, before keychain and temporary-file cleanup.
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child_process.pid, signal.SIGKILL)
                child_process.communicate()
                raise
            if child_process.returncode:
                raise subprocess.CalledProcessError(child_process.returncode, command)
    except (subprocess.SubprocessError, OSError, UnicodeError) as error:
        # Tool diagnostics can contain account names and keychain paths.
        raise RuntimeError(f"{label} failed. Check the local prerequisites; no release was published.") from error
    return stdout


@contextlib.contextmanager
def unlocked_keychain(config, password):
    """An optional secret-manager password is sent only to security's stdin."""
    if password is None:
        yield
        return
    # Apple's getpass buffer is limited by _PASSWORD_LEN in pwd.h.
    if not password or any(character in password for character in "\r\n\0") or len(password.encode()) > 128:
        raise RuntimeError("Signing password must be nonempty, single-line and at most 128 UTF-8 bytes.")
    # A detached session makes Apple's getpass read the pipe, never the user's tty.
    try:
        run("Unlock dedicated signing keychain", "/usr/bin/security", "unlock-keychain",
            config["keychain"], input=password + "\n", timeout=30)
        yield
    finally:
        run("Lock dedicated signing keychain", "/usr/bin/security", "lock-keychain", config["keychain"], timeout=30)


def settings(path):
    try:
        config = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise RuntimeError("Cannot read release settings. See docs/releases.md.") from error
    required = {"identity", "team_id", "keychain", "notary_profile", "node"}
    if not isinstance(config, dict) or set(config) not in (required, required | {"notary_keychain"}):
        raise RuntimeError("Release settings have missing or unknown fields.")
    if not all(isinstance(value, str) and value.strip() and "\n" not in value for value in config.values()):
        raise RuntimeError("Release settings must contain nonempty single-line strings.")
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", config["identity"]) or not re.fullmatch(r"[A-Z0-9]{10}", config["team_id"]):
        raise RuntimeError("Expected a certificate SHA-1 fingerprint and a ten-character team ID.")
    node = pathlib.Path(config["node"])
    if not node.is_absolute() or not node.is_file() or not os.access(node, os.X_OK):
        raise RuntimeError("Configure an absolute executable path to trusted Node 22 or newer.")
    config["node"] = str(node.resolve())
    for field in ("keychain", "notary_keychain"):
        if field in config:
            config[field] = str(pathlib.Path(config[field]).expanduser().resolve())
            if not pathlib.Path(config[field]).is_file():
                raise RuntimeError("Configured keychain is missing. Configure it locally before releasing.")
    return config


def clean_revision(revision, root=None):
    root = ROOT if root is None else root
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise RuntimeError("Pass the full reviewed commit SHA with --revision.")
    if run("Check complete source history", "/usr/bin/git", "--no-replace-objects", "rev-parse",
           "--is-shallow-repository", cwd=root).strip() != "false":
        raise RuntimeError("Release requires complete Git history. Use a non-shallow checkout.")
    if run("Check replacement refs", "/usr/bin/git", "--no-replace-objects", "for-each-ref",
           "--format=%(refname)", "refs/replace/", cwd=root).strip():
        raise RuntimeError("Git replacement references are not allowed in a release checkout.")
    if run("Check source revision", "/usr/bin/git", "--no-replace-objects", "rev-parse", "HEAD", cwd=root).strip() != revision:
        raise RuntimeError("The checked-out revision does not match --revision.")
    if run("Check source cleanliness", "/usr/bin/git", "--no-replace-objects", "status", "--porcelain", "--untracked-files=all", cwd=root).strip():
        raise RuntimeError("Commit or remove source changes before releasing.")
    entries = run("Check source index flags", "/usr/bin/git", "--no-replace-objects", "ls-files", "-v", "-z", cwd=root)
    if any(entry[0].islower() or entry[0] == "S" for entry in entries.split("\0") if entry):
        raise RuntimeError("Release index flags must not hide tracked files. Clear assume-unchanged and skip-worktree flags.")
    tree = run("Read checkout source tree", "/usr/bin/git", "--no-replace-objects", "ls-tree", "-rz", "--full-tree", revision, cwd=root)
    for record in tree.split("\0"):
        if not record:
            continue
        metadata, name = record.split("\t", 1)
        mode, kind, expected = metadata.split()
        file = root / name
        if kind != "blob" or mode not in {"100644", "100755"} or file.is_symlink() or not file.is_file():
            raise RuntimeError("Release checkout must contain the reviewed regular files.")
        data = file.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if actual != expected or bool(file.stat().st_mode & 0o111) != (mode == "100755"):
            raise RuntimeError("Release checkout bytes or executable modes differ from the reviewed tree.")


def test_reviewed_source(config, revision):
    """Run tests without importing ignored files from the maintainer's checkout."""
    expected_refs = set(run("Read source publication refs", "/usr/bin/git", "--no-replace-objects",
                            "for-each-ref", "--format=%(refname) %(objectname)", cwd=ROOT).splitlines())
    with tempfile.TemporaryDirectory(prefix="release-tests-") as temporary:
        source = pathlib.Path(temporary) / "source"
        run("Create isolated test checkout", "/usr/bin/git", "--no-replace-objects", "clone",
            "--no-hardlinks", "--no-checkout", "--template=", "--", str(ROOT), str(source))
        run("Select reviewed test revision", "/usr/bin/git", "--no-replace-objects",
            "-c", "core.hooksPath=/dev/null", "-c", "core.autocrlf=false",
            "checkout", "--detach", revision, cwd=source)
        # The clone's alias can target a different branch than the source's alias.
        run("Remove generated remote alias", "/usr/bin/git", "--no-replace-objects",
            "remote", "set-head", "origin", "--delete", cwd=source)
        run("Preserve all publication refs", "/usr/bin/git", "--no-replace-objects",
            "fetch", "--no-recurse-submodules", "--no-write-fetch-head", "origin",
            "+refs/*:refs/*", cwd=source)
        actual_refs = set(run("Read isolated publication refs", "/usr/bin/git", "--no-replace-objects",
                              "for-each-ref", "--format=%(refname) %(objectname)", cwd=source).splitlines())
        if not expected_refs <= actual_refs:
            raise RuntimeError("Isolated publication refs are incomplete or changed. Check Git ref visibility.")
        clean_revision(revision, root=source)
        run("Run full test suite", "/bin/bash", "scripts/test.sh", config["node"], sys.executable,
            "/usr/bin/jq", cwd=source)
        clean_revision(revision, root=source)


def extract_reviewed_source(archive, source, revision):
    """Reject export attributes that omit or rewrite reviewed source files."""
    tree = run("Read reviewed source tree", "/usr/bin/git", "--no-replace-objects",
               "ls-tree", "-rz", "--full-tree", revision)
    expected, directories = {}, set()
    for record in tree.split("\0"):
        if not record:
            continue
        metadata, name = record.split("\t", 1)
        mode, kind, oid = metadata.split()
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise RuntimeError("The reviewed tree must contain only regular source files.")
        expected[name] = oid
        directories.update(str(parent) + "/" for parent in pathlib.PurePosixPath(name).parents if str(parent) != ".")
    with zipfile.ZipFile(archive) as handle:
        seen, files = set(), set()
        for entry in handle.infolist():
            name = entry.filename
            if name in seen or name not in (directories if entry.is_dir() else expected):
                raise RuntimeError("Source archive paths do not match the reviewed tree.")
            seen.add(name)
            if entry.is_dir():
                continue
            data = handle.read(entry)
            # Git blob IDs include the object type and byte length, not just data.
            oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
            if oid != expected[name]:
                raise RuntimeError("Source archive bytes do not match the reviewed tree. Check Git export attributes.")
            files.add(name)
        if files != expected.keys():
            raise RuntimeError("Source archive is missing files from the reviewed tree. Check Git export attributes.")
        handle.extractall(source)


def verify(app, config):
    # codesign treats a leading '=' as inline source; without it this is a filename.
    requirement = (f'=anchor apple generic and identifier "{BUNDLE_ID}" and '
                   'certificate leaf[field.1.2.840.113635.100.6.1.13] exists and '
                   f'certificate leaf[subject.OU] = "{config["team_id"]}"')
    run("Verify Developer ID and bundle identity", "/usr/bin/codesign", "--verify", "--deep", "--strict",
        "-R", requirement, str(app))


def sign(app, config):
    original = shlex.split(run("Read keychain search list", "/usr/bin/security", "list-keychains", "-d", "user"))
    if not original:
        raise RuntimeError("Cannot safely preserve an empty keychain search list.")
    changed = config["keychain"] not in original
    try:
        if changed:
            run("Enable signing keychain temporarily", "/usr/bin/security", "list-keychains", "-d", "user", "-s",
                config["keychain"], *original)
        run("Sign using local keychain", "/usr/bin/codesign", "--force", "--options", "runtime", "--timestamp",
            "--keychain", config["keychain"], "--sign", config["identity"], str(app))
    finally:
        if changed:
            run("Restore keychain search list", "/usr/bin/security", "list-keychains", "-d", "user", "-s", *original)


def release(config, revision, password=None):
    clean_revision(revision)
    node_version = run("Check configured Node version", config["node"], "--version").strip()
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", node_version) or int(node_version[1:].split(".")[0]) < 22:
        raise RuntimeError("The configured Node executable must be version 22 or newer.")
    run("Check system JSON test tool", "/usr/bin/jq", "--version")
    identities = run("Check local signing identity", "/usr/bin/security", "find-identity", "-v", "-p",
                     "codesigning", config["keychain"])
    matches = [line for line in identities.splitlines()
               if config["identity"].upper() in line.upper() and '"Developer ID Application:' in line]
    if len(matches) != 1:
        raise RuntimeError("Developer ID Application identity is unavailable. Unlock or repair the local keychain.")
    auth = ["--keychain-profile", config["notary_profile"]]
    if "notary_keychain" in config:
        auth += ["--keychain", config["notary_keychain"]]
    run("Check saved notarization credentials", "/usr/bin/xcrun", "notarytool", "history", *auth,
        "--output-format", "json", timeout=120)
    test_reviewed_source(config, revision)
    clean_revision(revision)
    output = ROOT / "build/releases"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-", dir=output) as temporary:
        stage = pathlib.Path(temporary)
        archive = stage / "source.zip"
        run("Export exact source revision", "/usr/bin/git", "--no-replace-objects", "archive", "--format=zip", f"--output={archive}", revision)
        source = stage / "source"
        extract_reviewed_source(archive, source, revision)
        run("Build both Mac architectures", "/bin/bash", "scripts/build.sh", "--universal", cwd=source)
        app = source / "build/Creator Micro AI.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        version = info.get("CFBundleShortVersionString", "")
        if (info.get("CFBundleIdentifier") != BUNDLE_ID or not isinstance(version, str)
                or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)):
            raise RuntimeError("Release bundle has an unexpected identifier or version.")
        name = f"Creator-Micro-AI-{version}-{revision[:12]}"
        destination = output / name
        if destination.exists():
            raise RuntimeError("A release for this revision already exists; it will not be overwritten.")
        # Compilation and network waits do not need an unlocked private key.
        with unlocked_keychain(config, password):
            sign(app, config)
        verify(app, config)
        submission = stage / "submission.zip"
        run("Package notarization submission", "/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
            str(app), str(submission))
        response = run("Submit to Apple notarization", "/usr/bin/xcrun", "notarytool", "submit", str(submission),
                       *auth, "--wait", "--timeout", "15m", "--output-format", "json")
        try:
            accepted = json.loads(response).get("status") == "Accepted"
        except (ValueError, AttributeError):
            accepted = False
        if not accepted:
            raise RuntimeError("Apple did not accept this submission. Inspect its history locally; no release was published.")
        run("Staple notarization ticket", "/usr/bin/xcrun", "stapler", "staple", str(app))
        package = stage / "package"
        package.mkdir()
        download = package / f"{name}.zip"
        run("Package stapled app", "/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(download))
        extracted = stage / "verification"
        run("Extract final download", "/usr/bin/ditto", "-x", "-k", str(download), str(extracted))
        delivered = extracted / "Creator Micro AI.app"
        verify(delivered, config)
        for architecture in ("arm64", "x86_64"):
            run(f"Verify delivered {architecture} architecture", "/usr/bin/lipo",
                str(delivered / "Contents/MacOS/CreatorMicroAI"), "-verify_arch", architecture)
        run("Validate delivered ticket", "/usr/bin/xcrun", "stapler", "validate", str(delivered))
        run("Check Gatekeeper", "/usr/sbin/spctl", "--assess", "--type", "execute", str(delivered))
        digest = hashlib.sha256(download.read_bytes()).hexdigest()
        (package / "SHA256SUMS").write_text(f"{digest}  {download.name}\n")
        package.rename(destination)
    print(f"Verified release: build/releases/{name}")
    print("Not installed, launched, or uploaded to a release host. Physical acceptance remains separate.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=pathlib.Path, default=ROOT / "private/release.json")
    parser.add_argument("--revision", required=True, help="Full reviewed commit SHA")
    args = parser.parse_args()
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    try:
        if sys.platform != "darwin" or os.environ.get("GITHUB_ACTIONS") == "true":
            raise RuntimeError("Signing runs locally on macOS, not in GitHub Actions.")
        password = os.environ.pop("CREATOR_SIGNING_PASSWORD", None)
        config = settings(args.config)
        release(config, args.revision, password)
    except KeyboardInterrupt:
        print("Release interrupted; no new release was published.", file=sys.stderr)
        return 1
    except (RuntimeError, OSError) as error:
        # Never print raw OS errors, which may contain private paths.
        print(str(error) if isinstance(error, RuntimeError) else "Local release file operation failed.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
