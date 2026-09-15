"""Fail closed on common accidental disclosures and forbidden runtime capture APIs."""
import pathlib
import io
import os
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCAL_DIRECTORIES = {"build", "__pycache__", "node_modules", "private", ".swift-module-cache"}
EXCLUDED = {".git"} | LOCAL_DIRECTORIES
SECRET_PATTERNS = [
    rb"/Users/[A-Za-z0-9_.-]+/", rb"/home/[A-Za-z0-9_.-]+/",
    rb"gh[pousr]_[A-Za-z0-9]{20,}", rb"github_pat_[A-Za-z0-9_]{20,}",
    rb"sk-[A-Za-z0-9_-]{30,}", rb"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    rb"ops_[A-Za-z0-9_-]{20,}",
]
RUNTIME_BANNED = [
    "CGEvent.tapCreate", "NSEvent.addGlobalMonitor", "NSEvent.addLocalMonitor",
    "NSPasteboard", "AXURL", "URLSession", "NWConnection", "Logger(",
    "console.log", "console.error", "error.message", "error.stack", "createServer(",
    "readline", "kAXSelectedTextAttribute",
]

def findings(path, data):
    issues = []
    if (path.suffix.lower() == ".zip" or data.startswith((b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08"))
            or zipfile.is_zipfile(io.BytesIO(data))):
        issues.append("archive artifact must not be published")
    if any(re.search(pattern, data) for pattern in SECRET_PATTERNS):
        issues.append("possible credential or personal absolute path")
    if path.parts[0] == "helper":
        text = data.decode("utf-8", errors="replace")
        if any(token in text for token in RUNTIME_BANNED):
            issues.append("forbidden runtime capture, logging or network API")
        if path.suffix == ".swift" and re.search(r"\b(print|fputs|NSLog)\s*\(", text):
            issues.append("runtime logging is disabled by policy")
    if any(part.lower() in LOCAL_DIRECTORIES or part.lower().startswith(".env") or "backup" in part.lower() for part in path.parts) or path.name.lower() == ".ds_store" or path.suffix.lower() in {".pyc", ".log", ".har", ".trace", ".pem", ".p12", ".mobileprovision"}:
        issues.append("private local artifact must not be published")
    return issues

def git_output(root, *args):
    """Inspect this checkout without inherited Git repository overrides."""
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    return subprocess.check_output(["/usr/bin/git", "--no-replace-objects", *args], cwd=root,
                                   env=env, stderr=subprocess.DEVNULL)

def staged_blobs(root):
    """Read the index, independently of later worktree edits or removals."""
    try:
        entries = git_output(root, "ls-files", "--stage", "-z")
        for entry in entries.split(b"\0"):
            if not entry:
                continue
            metadata, raw_name = entry.split(b"\t", 1)
            mode, oid, stage = metadata.split()
            if mode not in {b"100644", b"100755"} or stage != b"0":
                raise ValueError("Git index requires publication review")
            data = git_output(root, "cat-file", "blob", oid.decode())
            yield raw_name.decode(), data
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        raise ValueError("Git index could not be safely inspected") from error

def main():
    errors = []
    for file in ROOT.rglob("*"):
        relative = file.relative_to(ROOT)
        if any(part.lower() in EXCLUDED for part in relative.parts):
            continue
        if file.name.lower() == ".ds_store" or file.suffix.lower() == ".pyc":
            continue
        if file.is_symlink():
            errors.append((relative, "symlink requires explicit publication review"))
        elif file.is_file():
            for issue in findings(relative, file.read_bytes()):
                errors.append((relative, issue))
    # Ignoring a file does not untrack it. Check the Git index as well.
    try:
        for name, data in staged_blobs(ROOT):
            errors.extend((name, issue) for issue in findings(pathlib.Path(name), data))
    except ValueError:
        errors.append(("Git index", "index inspection failed; publication is blocked"))
    for path, issue in errors:
        print(f"FAIL {path}: {issue}")
    if errors:
        return 1
    print("Privacy checks passed. This is a heuristic, not a guarantee or a substitute for review.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
