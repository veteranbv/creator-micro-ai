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
    # Build tools need the user's toolchain paths, not the invoking shell's secrets.
    environment = {key: value for key, value in os.environ.items() if key in {
        "PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL",
        "DEVELOPER_DIR", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET",
    }}
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                                timeout=timeout, check=True, env=environment,
                                input=input, start_new_session=input is not None)
    except (subprocess.SubprocessError, OSError) as error:
        # Tool diagnostics can contain account names and keychain paths.
        raise RuntimeError(f"{label} failed. Check the local prerequisites; no release was published.") from error
    return result.stdout


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
    required = {"identity", "team_id", "keychain", "notary_profile"}
    if not isinstance(config, dict) or set(config) not in (required, required | {"notary_keychain"}):
        raise RuntimeError("Release settings have missing or unknown fields.")
    if not all(isinstance(value, str) and value.strip() and "\n" not in value for value in config.values()):
        raise RuntimeError("Release settings must contain nonempty single-line strings.")
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", config["identity"]) or not re.fullmatch(r"[A-Z0-9]{10}", config["team_id"]):
        raise RuntimeError("Expected a certificate SHA-1 fingerprint and a ten-character team ID.")
    for field in ("keychain", "notary_keychain"):
        if field in config:
            config[field] = str(pathlib.Path(config[field]).expanduser().resolve())
            if not pathlib.Path(config[field]).is_file():
                raise RuntimeError("Configured keychain is missing. Configure it locally before releasing.")
    return config


def clean_revision(revision):
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise RuntimeError("Pass the full reviewed commit SHA with --revision.")
    if run("Check source revision", "git", "rev-parse", "HEAD").strip() != revision:
        raise RuntimeError("The checked-out revision does not match --revision.")
    if run("Check source cleanliness", "git", "status", "--porcelain", "--untracked-files=all").strip():
        raise RuntimeError("Commit or remove source changes before releasing.")


def verify(app, config):
    requirement = (f'=anchor apple generic and identifier "{BUNDLE_ID}" and '
                   'certificate leaf[field.1.2.840.113635.100.6.1.13] exists and '
                   f'certificate leaf[subject.OU] = "{config["team_id"]}"')
    run("Verify Developer ID and bundle identity", "codesign", "--verify", "--deep", "--strict",
        "-R", requirement, str(app))


def sign(app, config):
    original = shlex.split(run("Read keychain search list", "security", "list-keychains", "-d", "user"))
    if not original:
        raise RuntimeError("Cannot safely preserve an empty keychain search list.")
    changed = config["keychain"] not in original
    try:
        if changed:
            run("Enable signing keychain temporarily", "security", "list-keychains", "-d", "user", "-s",
                config["keychain"], *original)
        run("Sign using local keychain", "codesign", "--force", "--options", "runtime", "--timestamp",
            "--keychain", config["keychain"], "--sign", config["identity"], str(app))
    finally:
        if changed:
            run("Restore keychain search list", "security", "list-keychains", "-d", "user", "-s", *original)


def release(config, revision):
    clean_revision(revision)
    identities = run("Check local signing identity", "security", "find-identity", "-v", "-p",
                     "codesigning", config["keychain"])
    matches = [line for line in identities.splitlines()
               if config["identity"].upper() in line.upper() and '"Developer ID Application:' in line]
    if len(matches) != 1:
        raise RuntimeError("Developer ID Application identity is unavailable. Unlock or repair the local keychain.")
    auth = ["--keychain-profile", config["notary_profile"]]
    if "notary_keychain" in config:
        auth += ["--keychain", config["notary_keychain"]]
    run("Check saved notarization credentials", "xcrun", "notarytool", "history", *auth,
        "--output-format", "json", timeout=120)
    run("Run full test suite", "bash", "scripts/test.sh")
    clean_revision(revision)
    output = ROOT / "build/releases"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-", dir=output) as temporary:
        stage = pathlib.Path(temporary)
        archive = stage / "source.zip"
        run("Export exact source revision", "git", "archive", "--format=zip", f"--output={archive}", revision)
        source = stage / "source"
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(source)
        run("Build both Mac architectures", "bash", "scripts/build.sh", "--universal", cwd=source)
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
        sign(app, config)
        verify(app, config)
        submission = stage / "submission.zip"
        run("Package notarization submission", "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
            str(app), str(submission))
        response = run("Submit to Apple notarization", "xcrun", "notarytool", "submit", str(submission),
                       *auth, "--wait", "--timeout", "15m", "--output-format", "json")
        try:
            accepted = json.loads(response).get("status") == "Accepted"
        except (ValueError, AttributeError):
            accepted = False
        if not accepted:
            raise RuntimeError("Apple did not accept this submission. Inspect its history locally; no release was published.")
        run("Staple notarization ticket", "xcrun", "stapler", "staple", str(app))
        package = stage / "package"
        package.mkdir()
        download = package / f"{name}.zip"
        run("Package stapled app", "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(download))
        extracted = stage / "verification"
        run("Extract final download", "ditto", "-x", "-k", str(download), str(extracted))
        delivered = extracted / "Creator Micro AI.app"
        verify(delivered, config)
        run("Verify both delivered architectures", "lipo",
            str(delivered / "Contents/MacOS/CreatorMicroAI"), "-verify_arch", "arm64", "x86_64")
        run("Validate delivered ticket", "xcrun", "stapler", "validate", str(delivered))
        run("Check Gatekeeper", "spctl", "--assess", "--type", "execute", str(delivered))
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
        with unlocked_keychain(config, password):
            release(config, args.revision)
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
