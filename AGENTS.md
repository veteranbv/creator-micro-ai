# Project instructions

This is a fan-made configuration kit for Work Louder's Creator Micro 2, built on Input. Respect and credit that platform. Do not imply vendor endorsement or redistribute vendor firmware or code. The supplied device photograph may show the real branding and keycaps as a hardware reference. Matching functional keycap illustrations are permitted for the control reference. Do not extract Work Louder logos, wordmarks or other branding into project branding or an asset pack.

- This repository is the canonical development source. Publish only current product behavior and the instructions needed to use or maintain it. Every shipped macro must be assigned to a control.
- Read README, PRIVACY and docs/gotchas before changing behavior. Inspect actual code and current docs before proposing a fix.
- Preserve foreground-app action routing, all four layer mappings, the one-switch dictation bar and balanced dictation timing.
- No key recorders, clipboard reads, raw accessibility dumps, runtime action logs or network listeners. Tests use synthetic fixtures, never real conversations.
- Missing, ambiguous or truncated approval controls must do nothing. Y means Allow once, never Always allow. Never fall back to Return or typed y/n in a draft.
- Do not run hardware tests, change Accessibility settings or install a new live helper without explicit user authorization. Build and fixture tests do not need device access.
- Run `bash scripts/test.sh`. Record any physical verification separately. Do not label synthetic tests as hardware validation.
- Keep credentials in ignored local files or a secret manager. Never print environment values or copy a service-account token into this repo.
- Private reference projects and conversation context are not public attribution. Publish only information needed to use, maintain or credit this project. Never put actual private identifiers into regression fixtures or review comments.
- Use a GitHub no-reply commit email. Use rebase merging, not squash merging, and verify the final main author and committer identities. Run the full-history publication check before publishing.
- Use plain comments and docs, no em dashes. Commit messages must not include AI attribution.

## Pull requests and review

- Finish and test a coherent change locally, then run a local code and security review (`/code-review` and `/security-review` in Claude Code, or `codex review --base main` in Codex CLI) before asking for remote review.
- Use PRs for main. The owner requests remote Codex review for the exact pushed head; a new push needs a new request. Address every finding on the same PR and resolve its thread. After three rounds that still find substantive issues, stop and reconsider the change.
- Required checks are `quality` and `review-gate`, including for administrators. `review-gate` comes from `review-gate-trusted.yml` on `pull_request_target`: GitHub runs the default branch's copy, so a PR cannot rewrite it, and it checks out only the evaluator at the default-branch tip with a read-only token, never PR code. Do not bypass failed checks.
- Protection pins `review-gate` to the GitHub Actions app, not to that workflow, so a PR could add its own job of the same name. Merge only with `homelab pr merge <n> --repo veteranbv/creator-micro-ai --yes`, which counts the trusted run alone; never the merge button or auto-merge. The retrigger listens to `issue_comment` only, which runs the default branch's copy.
- No AI attribution in commits, titles or descriptions, and commits come from a person's identity, never an app or bot account; `review-gate` rejects both.

### Review guidelines

Reviewers (Codex, Claude Code, humans) apply these to every PR.

- Failure here means: recording, persisting or transmitting typed text, clipboard data, app content, raw device exceptions or action history; approval fallbacks that submit a draft, choose Always allow or act on missing, ambiguous or truncated controls; network listeners or runtime logging in the helper; device writes, Accessibility changes or other hardware effects without explicit user action; private exports, recordings, screenshots, preferences, device backups, credentials or private identifiers in public files or fixtures; workflows that run PR code with secrets or write tokens. Prioritize these.
- Transient accessibility labels used for selectors are expected; persisting or transmitting them is not. The safe result for an unclear approval control is no action.
- Flag changes that activate both wide-key switches, alter balanced dictation timing without physical evidence, or route action keys by layer instead of the foreground app.
- Report only issues the change introduces or makes worse; mark pre-existing problems as pre-existing.
- Every finding needs file:line evidence and a concrete failure scenario.
- At most three nitpicks per review; skip what the test suite and publication checks already enforce.
- Do not label synthetic or fixture tests as hardware validation.
- Start the summary with the number of findings; say plainly when nothing needs fixing.
