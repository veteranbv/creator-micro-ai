# Contributing

Start with a small change and a reproducible test. Check actual app labels or documented shortcuts rather than guessing. Do not change the workflow merely to make a test pass.

Run `bash scripts/test.sh`. Linux covers profile, bridge, privacy and review-policy checks. macOS additionally compiles the helper and runs synthetic accessibility-selection and shortcut-construction tests. These tests do not post keyboard events or inspect open conversations.

Hardware and app versions are part of compatibility. For an action-routing change, complete the matrix in docs/verification.md. Never use destructive commands as approval test fixtures; asking permission to list a disposable test directory is sufficient.

Use `codex/` for development branches. After the final push, the repository owner requests `@codex review <full current head SHA>`. The review gate waits for an actual matching Codex review, not an eyes reaction. Unresolved P0/P1 findings block the gate. Missing reviews, stale reviews or incomplete pagination do not silently pass. Resolve findings, rerun checks and request a new review when the head changes.

Do not submit screenshots of private conversations, production credentials, local preference exports, diagnostic recordings or device backups. See PRIVACY.md and SECURITY.md.

Put a space after `//` in source comments, including `// TODO:` and `// MARK:`.
The publication scanner treats ambiguous no-space text as a possible address,
even inside source files. It does not infer comments from line position or skip
multiline strings. Its URL check also decodes escaped slashes, escaped dots and
ASCII hex escapes, including braced Unicode escapes, in serialized text or regex
literals. Decoded backslashes count as URL separators, and nested URLs are checked
independently. HTTP, HTTPS,
FTP, WS and WSS addresses are checked even without the usual two slashes. The URL
check also removes ASCII tabs and newlines, including their short and hex escapes,
in a separate scan view. The original text is still checked. A passing
scan is not proof that all private data or arbitrary encodings have been detected;
review the content before publication.

Keep unrelated projects and private conversation context out of documentation, tests and PR descriptions. Use synthetic examples and a GitHub no-reply email. Run `python3 scripts/publication_check.py --all-history` before pushing. Rebase merging preserves the checked author identity; verify main's metadata after merge.
