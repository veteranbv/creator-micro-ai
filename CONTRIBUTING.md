# Contributing

Start with a small change and a reproducible test. Check actual app labels or documented shortcuts rather than guessing. Do not change the workflow merely to make a test pass.

Run `bash scripts/test.sh`. Linux covers profile, bridge, privacy and review-policy checks. macOS additionally compiles the helper and runs synthetic accessibility-selection and shortcut-construction tests. These tests do not post keyboard events or inspect open conversations.

Hardware and app versions are part of compatibility. For an action-routing change, complete the matrix in docs/verification.md. Never use destructive commands as approval test fixtures; asking permission to list a disposable test directory is sufficient.

Use `codex/` for development branches. After the final push, the repository owner requests `@codex review <full current head SHA>`. The review gate waits for an actual matching Codex review, not an eyes reaction. Unresolved P0/P1 findings block the gate. Missing reviews, stale reviews or incomplete pagination do not silently pass. Resolve findings, rerun checks and request a new review when the head changes.

Do not submit screenshots of private conversations, production credentials, local preference exports, diagnostic recordings or device backups. See PRIVACY.md and SECURITY.md.

Put a space after `//` in source comments, including `// TODO:` and `// MARK:`.
The publication scanner treats ambiguous no-space text as a possible address,
even inside source files. It does not infer comments from line position or skip
multiline strings. The URL scan uses one conservative escape-decoding pass:
byte hex escapes, ASCII fixed-width or braced Unicode escapes, JavaScript legacy
octal escapes, short control escapes, ASCII identity escapes and escaped line
continuations. Repeated backslashes before numeric escapes are accepted for
serialized text. Repeated backslashes before a plain hostname or IPv6 address
become two URL separators without consuming the host's first character. Malformed
numeric values and non-ASCII Unicode values are not decoded. Decoded backslashes
count as URL separators, not a request to decode another layer. Nested URLs are
checked independently. HTTP, HTTPS, FTP, WS and WSS addresses are checked even
without the usual two slashes. A second view removes ASCII tabs and newlines;
the first decoded view remains checked. Domain, email and credential checks also
inspect the original bytes. This is not a source-language parser: it does not
execute code, join expressions, expand templates or decode arbitrary encodings.
A passing scan is not proof that all private data has been detected. Review the
content before publication. Ambiguous backslashes can require review even when
their literal URL-separator interpretation would use an allowed host.

All publication Git reads disable replacement objects. Index entries, trees,
commits and tags must be checked using their stored bytes, not local substitutes.
Commit scanning includes all headers and continuation lines, not only the message
and display identities shown by Git's formatted output.

Keep unrelated projects and private conversation context out of documentation, tests and PR descriptions. Use synthetic examples and a GitHub no-reply email. Run `python3 scripts/publication_check.py --all-history` before pushing. Rebase merging preserves the checked author identity; verify main's metadata after merge.
