# Contributing

Start with a small change and a reproducible test. Check actual app labels or documented shortcuts rather than guessing. Do not change the workflow merely to make a test pass.

Run `bash scripts/test.sh`. Linux covers profile, bridge, privacy and review-policy checks. macOS additionally compiles the helper and runs synthetic accessibility-selection and shortcut-construction tests. These tests do not post keyboard events or inspect open conversations.

Hardware and app versions are part of compatibility. For an action-routing change, complete the matrix in docs/verification.md. Never use destructive commands as approval test fixtures; asking permission to list a disposable test directory is sufficient.

Use `codex/` for development branches. After the final push, the repository owner requests `@codex review <full current head SHA>`. The review gate waits for an actual matching Codex review, not an eyes reaction. Unresolved P0/P1 findings block the gate. Missing reviews, stale reviews or incomplete pagination do not silently pass. Resolve findings, rerun checks and request a new review when the head changes.

Do not submit screenshots of private conversations, production credentials, local preference exports, diagnostic recordings or device backups. See PRIVACY.md and SECURITY.md.

Put a space after `//` in source comments, including `// TODO:` and `// MARK:`.
The publication scanner treats ambiguous no-space text as a possible address,
even inside source files. It does not infer comments from line position or skip
multiline strings. The URL scan uses bounded, non-recursive escape decoding:
byte hex escapes, ASCII fixed-width or braced Unicode escapes, JavaScript legacy
octal escapes, short control escapes, ASCII identity escapes and escaped line
continuations. Repeated backslashes before numeric escapes are accepted for
serialized text. Repeated backslashes before a plain hostname or IPv6 address
become two URL separators without consuming the host's first character. A complete
hostname is preserved even when its prefix looks like a numeric escape. A second
interpretation prioritizes numeric escapes, so serialized dots cannot silently
extend an allowed hostname. Both interpretations are checked independently;
neither feeds into the other. Malformed
numeric values and non-ASCII Unicode values are not decoded. Decoded backslashes
count as URL separators, not a request to decode another layer. Nested URLs are
checked independently. HTTP, HTTPS, FTP, WS and WSS addresses are checked even
without the usual two slashes. Scheme-relative addresses can start with more
than two slashes. A second URL view removes ASCII tabs and newlines;
the first decoded view remains checked. Domain and email checks inspect both
original and escape-decoded text. Source-reference exceptions retain their original
locations after decoding, so a real path cannot exempt a separate endpoint.
Credential checks inspect the original bytes. This is not a source-language parser: it does not
execute code, join expressions, expand templates or decode arbitrary encodings.
A passing scan is not proof that all private data has been detected. Review the
content before publication. Ambiguous backslashes can require review even when
their literal URL-separator interpretation would use an allowed host.

All publication Git reads disable replacement objects and remove inherited
`GIT_` environment overrides. They inspect this checkout's repository and index,
not an alternate location selected by the shell. PATH is left unchanged.
Index entries, trees, commits and tags must be checked using their stored bytes,
not local substitutes.
Commit scanning includes all headers and continuation lines, not only the message
and display identities shown by Git's formatted output.
Complete commit and annotated-tag payloads must be valid UTF-8. Other encodings
block publication rather than skipping the URL, domain and email checks. This
requirement does not change the separate review of binary assets.

Keep unrelated projects and private conversation context out of documentation, tests and PR descriptions. Use synthetic examples and a GitHub no-reply email. Run `python3 scripts/publication_check.py --all-history` before pushing. Rebase merging preserves the checked author identity; verify main's metadata after merge.
