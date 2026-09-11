# Contributing

Start with a small change and a reproducible test. Check actual app labels or documented shortcuts rather than guessing. Do not change the workflow merely to make a test pass.

Run `bash scripts/test.sh`. Linux covers profile, bridge, privacy and review-policy checks. macOS additionally compiles the helper and runs synthetic accessibility-selection and shortcut-construction tests. These tests do not post keyboard events or inspect open conversations.

Hardware and app versions are part of compatibility. For an action-routing change, complete the matrix in docs/verification.md. Never use destructive commands as approval test fixtures; asking permission to list a disposable test directory is sufficient.

Use `codex/` for development branches. After the final push, the repository owner requests `@codex review <full current head SHA>`. The review gate waits for an actual matching Codex review, not an eyes reaction. Unresolved P0/P1 findings block the gate. Missing reviews, stale reviews or incomplete pagination do not silently pass. Resolve findings, rerun checks and request a new review when the head changes.

Do not submit screenshots of private conversations, production credentials, local preference exports, diagnostic recordings or device backups. See PRIVACY.md and SECURITY.md.

Keep unrelated projects and private conversation context out of documentation, tests and PR descriptions. Use synthetic examples and a GitHub no-reply email. Run `python3 scripts/publication_check.py --all-history` before pushing. Rebase merging preserves the checked author identity; verify main's metadata after merge.
