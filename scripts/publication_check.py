"""Check publication content and Git identities without echoing matched values."""
import argparse
import ast
from ast import Call, Name
import hashlib
import pathlib
import re
from urllib.parse import urlsplit

from privacy_check import findings as privacy_findings, git_output, staged_blobs
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
# Schemes establish an authority regardless of host syntax. A bare authority
# must start at a token boundary, not inside an XML public identifier.
# Look ahead so an allowed outer URL cannot consume a nested authority.
URL = re.compile(
    rb"(?=(\b(?:https?|ftp|wss?):[/\\]*[^/\\\s<>\"'][^\s<>\"']*"
    rb"|\b[a-zA-Z][a-zA-Z0-9+.-]*:/{2}[^\s<>\"']+"
    rb"|(?<![\w+./:-])/{2,}(?=[\w%~!$&*+,;=:@.-]|\[[0-9a-fA-FvV:])[^\s<>\"']+))", re.IGNORECASE)
# These exact references are files, not hosts. URLs never use this exception.
FILE_REFERENCES = {
    "README.md", "CONTRIBUTING.md", "PRIVACY.md", "AGENTS.md", "NOTICE.md", "SECURITY.md",
    "gotchas.md", "repository-admin.md", "setup.md", "verification.md", "releases.md",
    "build.sh", "device.sh", "icon.sh", "test.sh", "install.py", "example.py", "fixture.py", "notes.md",
    "release.py", "source.zip", "submission.zip",
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
    "release.run", "download.name", "self.fail",
    "setupItem.target", "DispatchQueue.global", "pipe.fileHandleForReading.read",
    "NSWorkspace.shared.open", "back.target", "next.target", "relaunch.run",
    "self.health", "self.operation.run", "window.center", "app.run",
    # Fixed macOS System Settings pane identifier, not a network host.
    "com.apple.preference.security",
}
SOURCE_EXTENSIONS = {".py", ".js", ".swift", ".yml", ".yaml"}
PYTHON_MEMBERS = {"release.run", "download.name", "self.fail"}
SWIFT_MEMBERS = {"children.map"}
PATH_REFERENCES = {"releases.md", "release.py", "source.zip", "submission.zip"}
EMAIL = re.compile(rb"[a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})")


def python_reference_spans(name, data):
    if pathlib.Path(name).suffix != ".py":
        return [], [], []
    try:
        tree = ast.parse(data)
    except (SyntaxError, ValueError):
        return [], [], []
    offsets = [0]
    for line in data.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    member_spans, path_spans, url_pattern_spans = [], [], []
    for node in ast.walk(tree):
        if (name == "scripts/publication_check.py" and isinstance(node, ast.Assign)
                and any(isinstance(url_target, Name) and url_target.id == "URL" for url_target in node.targets)
                and isinstance(node.value, Call) and isinstance(url_function := node.value.func, ast.Attribute)
                and isinstance(url_function.value, Name) and url_function.value.id == "re"
                and url_function.attr == "compile" and node.value.args
                and isinstance(node.value.args[0], ast.Constant)):
            pattern = node.value.args[0]
            url_pattern_spans.append((offsets[pattern.lineno - 1] + pattern.col_offset,
                                      offsets[pattern.end_lineno - 1] + pattern.end_col_offset))
        candidates = [node] if isinstance(node, ast.Attribute) else []
        # The checker's explicit policy table is data, not a connection endpoint.
        if name == "scripts/publication_check.py" and isinstance(node, ast.Assign) and isinstance(node.value, ast.Set):
            if any(isinstance(assignment_target, Name) and assignment_target.id in {"SOURCE_REFERENCES", "PYTHON_MEMBERS", "SWIFT_MEMBERS", "FILE_REFERENCES", "PATH_REFERENCES"} for assignment_target in node.targets):
                candidates = [value for value in node.value.elts if isinstance(value, ast.Constant) and value.value in PYTHON_MEMBERS | SWIFT_MEMBERS | PATH_REFERENCES]
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div) and isinstance(node.right, ast.Constant):
            if node.right.value in PATH_REFERENCES:
                candidates = [node.right]
        # Reviewed fixture tables contain synthetic filenames and members.
        # Do not exempt other strings or endpoint arguments in the test file.
        if name == "tests/test_publication.py" and isinstance(node, ast.For) and isinstance(node.iter, ast.Tuple):
            candidates = [value for value in node.iter.elts if isinstance(value, ast.Constant) and value.value in PATH_REFERENCES]
            if all(isinstance(value, ast.Constant) and isinstance(value.value, str) for value in node.iter.elts):
                if {value.value for value in node.iter.elts} == PYTHON_MEMBERS:
                    candidates = node.iter.elts
        # Literal scanner inputs in this fixture file are synthetic test data.
        if name == "tests/test_publication.py" and isinstance(node, Call):
            call_target = node.func
            if isinstance(call_target, Name) and call_target.id == "content_findings" and len(node.args) > 1 and isinstance(node.args[1], ast.Constant):
                candidates = [node.args[1]]
            if isinstance(call_target, Name) and call_target.id == "git" and node.args and isinstance(node.args[0], ast.Constant):
                if node.args[0].value in {"add", "rm"}:
                    candidates = [value for value in node.args[1:] if isinstance(value, ast.Constant) and value.value in PATH_REFERENCES]
        for candidate in candidates:
            start = offsets[candidate.lineno - 1] + candidate.col_offset
            end = offsets[candidate.end_lineno - 1] + candidate.end_col_offset
            if isinstance(candidate, ast.Constant):
                (member_spans if candidate.value in PYTHON_MEMBERS | SWIFT_MEMBERS else path_spans).append((start, end))
            elif data[start:end].decode() in PYTHON_MEMBERS:
                member_spans.append((start, end))
    return member_spans, path_spans, url_pattern_spans


def swift_member_spans(name, data):
    """Locate narrow member exceptions outside Swift strings and comments.

    Interpolated expressions remain inside the string for this check. Unknown
    slash syntax stops exemptions rather than guessing whether it is a regex.
    """
    if pathlib.Path(name).suffix != ".swift":
        return []
    spans, index = [], 0
    scopes = [("code", None)]
    string_start = re.compile(rb'(#+)?("""|")')
    while index < len(data):
        kind, state = scopes[-1]
        if kind == "string":
            closing, escape = state
            if data.startswith(escape + b"(", index):
                scopes.append(("interpolation", 1))
                index += len(escape) + 1
            elif data.startswith(escape, index):
                index += len(escape) + 1
            elif data.startswith(closing, index):
                scopes.pop()
                index += len(closing)
            else:
                index += 1
            continue
        if data.startswith(b"//", index):
            end = data.find(b"\n", index)
            index = len(data) if end < 0 else end + 1
        elif data.startswith(b"/*", index):
            depth, index = 1, index + 2
            while index < len(data) and depth:
                if data.startswith(b"/*", index):
                    depth, index = depth + 1, index + 2
                elif data.startswith(b"*/", index):
                    depth, index = depth - 1, index + 2
                else:
                    index += 1
        elif match := string_start.match(data, index):
            hashes = match[1] or b""
            scopes.append(("string", (match[2] + hashes, b"\\" + hashes)))
            index = match.end()
        elif data[index:index + 1] == b"/":
            break
        elif kind == "interpolation" and data[index:index + 1] in (b"(", b")"):
            depth = state + (1 if data[index:index + 1] == b"(" else -1)
            if depth:
                scopes[-1] = (kind, depth)
            else:
                scopes.pop()
            index += 1
        else:
            match = DOMAIN.match(data, index)
            if match:
                if len(scopes) == 1 and match[0].decode() in SWIFT_MEMBERS:
                    spans.append(match.span())
                index = match.end()
            else:
                index += 1
    return spans


def url_scan_view(data, *, numeric_first=False):
    """Decode one conservative escape layer without evaluating source code."""
    separators = rb"(?P<separators>\\{2,})(?=[A-Za-z0-9_.~-]+(?:[/\s<>\"'?#:]|$)|\[[0-9a-fA-FvV:.]+\])"
    numeric = (
        rb"\\+(?:u00(?P<unicode>[0-7][0-9a-fA-F])|x(?P<hex>[0-9a-fA-F]{2})|u\{0*(?P<braced>[0-7]?[0-9a-fA-F])\}"
        rb"|(?P<octal>[0-3][0-7]{0,2}|[4-7][0-7]?)"
        rb"|(?P<continuation>\r\n|[\r\n]|\xe2\x80[\xa8\xa9]))")
    alternatives = (numeric, separators) if numeric_first else (separators, numeric)
    escapes = re.compile(b"|".join(alternatives) + rb"|\\(?P<simple>[^ux0-7\r\n\x80-\xff])")
    controls = {b"b": b"\b", b"f": b"\f", b"n": b"\n", b"r": b"\r", b"t": b"\t", b"v": b"\v"}
    def decode(match):
        if match.lastgroup == "separators":
            return b"//"
        if match.lastgroup == "continuation":
            return b""
        if match.lastgroup == "simple":
            value = controls.get(match["simple"], match["simple"])
        else:
            value = bytes([int(match[match.lastgroup], 8 if match.lastgroup == "octal" else 16)])
        # Network URL parsing treats backslashes as separators, not another escape layer.
        return value.replace(b"\\", b"/")
    return escapes.sub(decode, data)


def content_findings(name, data, *, path_context=False, require_utf8=False):
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
        if require_utf8:
            issues.append("Git metadata must be valid UTF-8 for publication review")
        return issues  # Binary metadata is reviewed separately, not treated as prose.
    member_spans, path_spans, url_pattern_spans = python_reference_spans(name, data)
    member_spans += swift_member_spans(name, data)
    scan_data = data
    for start, end in url_pattern_spans:
        # Reorder this equivalent regex character class before escape decoding.
        # Otherwise the scanner's own slash/backslash/whitespace exclusion
        # becomes a synthetic three-slash URL. No pattern text is exempted.
        pattern = scan_data[start:end].replace(rb"[^/" + b"\\" * 3 + b"s", rb"[^\s/" + b"\\" * 2)
        scan_data = scan_data[:start] + pattern + scan_data[end:]
    # Scan a decoded view for serialized URLs, without changing source offsets.
    # Be conservative: source comments and multiline strings are not exempt.
    decoded_views = []
    for numeric_first in (False, True):
        decoded = url_scan_view(scan_data, numeric_first=numeric_first)
        if not any(decoded == view for view, _ in decoded_views):
            decoded_views.append((decoded, numeric_first))
    # WHATWG parsing removes ASCII tabs and newlines, including inside schemes.
    # Retain the original view so joining separate lines cannot hide a match.
    url_data = b"\n".join(view + b"\n" + view.translate(None, b"\t\r\n") for view, _ in decoded_views)
    for match in URL.finditer(url_data):
        # Only visibly generic secret-reference examples belong in public docs.
        # Markdown's closing code fence may adjoin the example in the joined view.
        if re.fullmatch(rb"op:/{2}YOUR_[A-Z_]+/YOUR_[A-Z_]+/[a-z-]+", match[1].split(b"`", 1)[0]):
            continue
        # WHATWG network schemes accept missing or repeated slash/backslash
        # separators. Normalize those forms before the strict authority parser.
        address = re.sub(rb"^((?:https?|ftp|wss?):)[/\\]*", rb"\1//", match[1], flags=re.IGNORECASE)
        address = re.sub(rb"^/{3,}", b"//", address)
        try:
            host = urlsplit(address.replace(b"\\", b"/").decode()).hostname
        except ValueError:
            host = None
        if not host or host.lower() not in ALLOWED_DOMAINS:
            issues.append("unapproved URL host requires publication review")
            break
    for view, numeric_first in [(data, False)] + [(view, mode) for view, mode in decoded_views if view != data]:
        # Keep exceptions tied to original AST nodes after escape lengths change.
        def view_spans(spans):
            return spans if view is data else [
                (len(url_scan_view(scan_data[:start], numeric_first=numeric_first)),
                 len(url_scan_view(scan_data[:end], numeric_first=numeric_first)))
                for start, end in spans]
        members, paths = view_spans(member_spans), view_spans(path_spans)
        for match in DOMAIN.finditer(view):
            token = match.group().decode()
            if token in FILE_REFERENCES:
                if token not in PATH_REFERENCES or path_context or view[match.start() - 1:match.start()] == b"/":
                    continue
                if any(start <= match.start() and match.end() <= end for start, end in paths):
                    continue
            if token in PYTHON_MEMBERS | SWIFT_MEMBERS:
                if any(start <= match.start() and match.end() <= end for start, end in members):
                    continue
            elif pathlib.Path(name).suffix in SOURCE_EXTENSIONS and token in SOURCE_REFERENCES:
                continue
            if token.rsplit(".", 1)[-1].lower() in PUBLIC_TLDS and token.lower() not in ALLOWED_DOMAINS:
                issues.append("unapproved domain requires publication review")
                break
        for match in EMAIL.finditer(view):
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
    return privacy_findings(pathlib.Path(name), b"") + content_findings("repository-path", "\n".join(candidates).encode(), path_context=True)


def git(*args):
    return git_output(ROOT, *args)


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
                issues.extend((oid[:12], issue) for issue in content_findings("tag-message", data, require_utf8=True))
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
    try:
        for name, data in staged_blobs(ROOT):
            issues.extend((name, issue) for issue in path_findings(name))
            issues.extend((name, issue) for issue in content_findings(name, data))
    except ValueError:
        issues.append(("Git index", "index inspection failed; publication is blocked"))
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
        data = git("cat-file", "commit", commit)
        issues.extend((commit[:12], issue) for issue in content_findings("commit-object", data, require_utf8=True))
        author, committer = git("show", "-s", "--format=%ae%x00%ce", commit).decode().strip().split("\0", 1)
        if not identity_allowed(author) or not identity_allowed(committer):
            issues.append((commit[:12], "non-private commit email"))
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
