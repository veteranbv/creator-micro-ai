# Project instructions

This is a fan-made configuration kit for Work Louder's Creator Micro 2, built on Input. Respect and credit that platform. Do not imply vendor endorsement or redistribute vendor firmware, code, logos or keycap art.

- This repository is the canonical development source. Publish only current product behavior and the instructions needed to use or maintain it. Every shipped macro must be assigned to a control.
- Read README, PRIVACY and docs/gotchas before changing behavior. Inspect actual code and current docs before proposing a fix.
- Preserve foreground-app action routing, all four layer mappings, the one-switch dictation bar and balanced dictation timing.
- No key recorders, clipboard reads, raw accessibility dumps, runtime action logs or network listeners. Tests use synthetic fixtures, never real conversations.
- Missing, ambiguous or truncated approval controls must do nothing. Y means Allow once, never Always allow. Never fall back to Return or typed y/n in a draft.
- Do not run hardware tests, change Accessibility settings or install a new live helper without explicit user authorization. Build and fixture tests do not need device access.
- Run `bash scripts/test.sh`. Record any physical verification separately. Do not label synthetic tests as hardware validation.
- Use PRs for main. Require quality and review-gate, including for administrators. A maintainer posts `@codex review <full current head SHA>` after the last push. New pushes need a new review request. Do not bypass failed checks.
- Keep credentials in ignored local files or a secret manager. Never print environment values or copy a service-account token into this repo.
- Private reference projects and conversation context are not public attribution. Publish only information needed to use, maintain or credit this project. Never put actual private identifiers into regression fixtures or review comments.
- Use a GitHub no-reply commit email. Use rebase merging, not squash merging, and verify the final main author and committer identities. Run the full-history publication check before publishing.
- Use plain comments and docs, no em dashes. Commit messages must not include AI attribution.

## Code Review Rules

- Flag any path that records typed text, clipboard data, app content, raw device exceptions or action history. Transient accessibility labels used for selectors are expected; persisting or transmitting them is not.
- Flag approval fallbacks that submit a draft, choose Always allow or act on ambiguous/truncated controls. The safe result is no action.
- Flag changes that activate both wide-key switches, alter balanced dictation timing without physical evidence, or route action keys by layer instead of the foreground app.
