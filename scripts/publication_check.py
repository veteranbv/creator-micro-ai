"""Check publication content and Git identities without echoing matched values."""
import argparse
import hashlib
import pathlib
import re
import subprocess
from urllib.parse import urlsplit

from privacy_check import findings as privacy_findings
from artwork_metadata import metadata_clean, sanitized_icon

ROOT = pathlib.Path(__file__).resolve().parents[1]
ALLOWED_DOMAINS = {
    "github.com", "docs.github.com", "cli.github.com", "veteranbv.github.io",
    "worklouder.cc", "www.apple.com", "example.test", "users.noreply.github.com",
    "data.iana.org", "www.w3.org",
}
DOMAIN = re.compile(rb"(?<![\w.-])(?:[a-zA-Z0-9-]+\.)+(?:[a-zA-Z]{2,63}|xn--[a-zA-Z0-9-]+)(?![\w.-])")
PUBLIC_TLDS = {
    line.lower() for line in pathlib.Path(__file__).with_name("public-tlds.txt").read_text().splitlines()
    if line and not line.startswith("#")
} | {"test", "local", "internal", "invalid"}
URL = re.compile(rb"https?://[^\s<>\"']+", re.IGNORECASE)
# These exact references are files, not hosts. URLs never use this exception.
FILE_REFERENCES = {
    "README.md", "CONTRIBUTING.md", "PRIVACY.md", "AGENTS.md", "NOTICE.md", "SECURITY.md",
    "gotchas.md", "repository-admin.md", "setup.md", "verification.md",
    "build.sh", "device.sh", "icon.sh", "test.sh", "install.py", "example.py", "fixture.py", "notes.md",
    "ChatGPT.app", "Claude.app", "input.app", "AI.app",
}
# DNS suffixes also occur in source-language member expressions. Keep these
# exceptions exact and source-only; do not use them to exempt prose or URLs.
SOURCE_REFERENCES = {
    "f.bot", "match.group", "subprocess.run", "self.data", "m.group", "Date.now",
    "mode.name", "id.id", "self.press", "JSONSerialization.data", "handle.read", "Darwin.read",
    "item.menu", "quit.target", "task.run", "application.run", "labels.map",
    "source.name", "path.parts", "re.search", "relative.parts", "largeRequest.group",
    "pair.group", "twoButtonTree.group", "tree.group", "actions.map", "l.name", "m.id",
    "p.macros.map", "sectors.map", "events.map", "user.email", "user.name",
    "next.map", "controls.chat", "temporary.name", "0.radio", "self.radio",
    "file.name", "action.properties", "cap.events.click", "cap.properties", "reads.read",
    "ids.caps.children.map", "item.events", "item.properties", "item.style", "layer.events.click",
}
SOURCE_EXTENSIONS = {".py", ".js", ".swift", ".yml", ".yaml"}
EMAIL = re.compile(rb"[a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})")


def content_findings(name, data):
    issues = privacy_findings(pathlib.Path(name), data)
    if name.lower().endswith(".png") and not metadata_clean(data):
        issues.append("artwork metadata requires sanitization")
    if name.lower().endswith(".icns") or data.startswith(b"icns"):
        try:
            clean = sanitized_icon(data) == data
        except ValueError:
            clean = False
        if not clean:
            issues.append("icon metadata requires sanitization")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return issues  # Binary metadata is reviewed separately, not treated as prose.
    for match in URL.finditer(data):
        try:
            host = urlsplit(match.group().decode()).hostname
        except ValueError:
            host = None
        if not host or host.lower() not in ALLOWED_DOMAINS:
            issues.append("unapproved URL host requires publication review")
            break
    for match in DOMAIN.finditer(data):
        token = match.group().decode()
        if token in FILE_REFERENCES:
            continue
        if pathlib.Path(name).suffix in SOURCE_EXTENSIONS and token in SOURCE_REFERENCES:
            continue
        if token.rsplit(".", 1)[-1].lower() in PUBLIC_TLDS and token.lower() not in ALLOWED_DOMAINS:
            issues.append("unapproved domain requires publication review")
            break
    for match in EMAIL.finditer(data):
        if match.group().lower() != b"noreply@github.com" and match[1].lower() not in {b"users.noreply.github.com", b"example.test"}:
            issues.append("personal email is not publication-safe")
            break
    return issues


def identity_allowed(email):
    return email == "noreply@github.com" or bool(re.fullmatch(
        r"[a-zA-Z0-9+_.-]+@users\.noreply\.github\.com", email))


def path_findings(name):
    # Check each component and dotted prefix so adding .txt cannot hide a host.
    candidates = [name]
    for part in pathlib.PurePosixPath(name).parts:
        pieces = part.split(".")
        for end in range(1, len(pieces) + 1):
            candidate = ".".join(pieces[:end])
            # The test suffix is a source convention, not a hostname. Earlier
            # prefixes still expose a host embedded before that suffix.
            if part.endswith(".test.js") and candidate == part[:-3]:
                continue
            candidates.append(candidate)
    return privacy_findings(pathlib.Path(name), b"") + content_findings("repository-path", "\n".join(candidates).encode())


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def tree_findings(tree, seen):
    issues = []
    for entry in git("ls-tree", "-rz", tree).split(b"\0"):
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        mode, kind, oid = metadata.decode().split()
        name = raw_name.decode()
        issues.extend((name, issue) for issue in path_findings(name))
        if mode in {"120000", "160000"}:
            issues.append((name, "symlink or submodule needs publication review"))
            continue
        key = (oid, name)
        if key not in seen:
            seen.add(key)
            issues.extend((name, issue) for issue in content_findings(name, git("cat-file", "blob", oid)))
    return issues


def tag_findings():
    issues, seen = [], set()
    for line in git("for-each-ref", "--format=%(objectname)%00%(refname:strip=2)", "refs/tags").decode().splitlines():
        oid, name = line.split("\0", 1)
        issues.extend(("refs/tags/" + name, issue) for issue in path_findings(name))
        while oid not in seen:
            seen.add(oid)
            kind = git("cat-file", "-t", oid).decode().strip()
            if kind == "tag":
                data = git("cat-file", "tag", oid)
                header = data.partition(b"\n\n")[0]
                tagger = re.search(rb"(?m)^tagger .* <([^<>]+)> ", header)
                if not tagger or not identity_allowed(tagger[1].decode(errors="replace")):
                    issues.append((oid[:12], "non-private tagger email"))
                issues.extend((oid[:12], issue) for issue in content_findings("tag-message", data))
                target = re.search(rb"(?m)^object ([0-9a-f]+)$", header)
                if not target:
                    issues.append((oid[:12], "invalid tag target"))
                    break
                oid = target[1].decode()
            elif kind == "blob":
                issues.extend((oid[:12], issue) for issue in content_findings("tag-blob", git("cat-file", "blob", oid)))
                break
            elif kind == "tree":
                issues.extend(tree_findings(oid, set()))
                break
            else:
                break
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all-history", action="store_true")
    args = parser.parse_args()
    issues = tag_findings()
    # Include new source files before staging, but leave ignored private files alone.
    for name in git("ls-files", "--cached", "--others", "--exclude-standard", "-z").decode().split("\0"):
        if not name:
            continue
        issues.extend((name, issue) for issue in path_findings(name))
        file = ROOT / name
        if file.is_file():
            issues.extend((name, issue) for issue in content_findings(name, file.read_bytes()))
    commits = git("rev-list", "--all" if args.all_history else "HEAD").decode().splitlines()
    seen = set()
    for commit in commits:
        author, committer, author_name, committer_name, message = git(
            "show", "-s", "--format=%ae%x00%ce%x00%an%x00%cn%x00%B", commit).decode().split("\0", 4)
        if not identity_allowed(author) or not identity_allowed(committer):
            issues.append((commit[:12], "non-private commit email"))
        issues.extend((commit[:12], issue) for issue in content_findings("commit-message", message.encode()))
        for name in (author_name, committer_name):
            issues.extend((commit[:12], issue) for issue in content_findings("commit-identity", name.encode()))
        issues.extend(tree_findings(commit, seen))
    for name, issue in sorted(set(issues)):
        location = "path-sha256:" + hashlib.sha256(name.encode()).hexdigest()[:12] if path_findings(name) else name
        print(f"FAIL {location}: {issue}")
    if issues:
        return 1
    print(f"Publication checks passed for {len(commits)} commits. Context and binary metadata still require human review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
