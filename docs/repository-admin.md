# Repository administration

This project requires automated tests and an exact-commit Codex review before changes merge.

## GitHub configuration

Enable Actions and the Codex GitHub integration for this repository. Make `quality` and `review-gate` required checks on main, with up-to-date branches, administrator enforcement, no force pushes, no branch deletion and resolved conversations required. Require PRs; a solo-maintainer repo can use zero mandatory human approvals because the separate Codex gate is required. Do not treat the workflow YAML alone as live branch protection.

After the final push, the owner posts a standalone `@codex review <full current head SHA>` comment. A new head requires a new request. The gate rejects missing, unavailable, stale or incomplete reviews and unresolved P0/P1 findings. Reaction-only acknowledgments are not reviews.

The gate's Python code is checked out from the PR's base SHA, not contributor-controlled code. The retrigger workflow only reruns the existing check job and never checks out or executes a PR. It uses Actions write permission solely for reruns. The gate itself has read-only permissions. CI runs candidate tests with read-only permissions and no deployment credentials.

Review workflow edits manually. Required status-check names alone do not make a PR-controlled workflow immutable; this is not a security boundary against a contributor who rewrites the workflow. Automatic merging is not enabled. Require stronger organization-level workflow rules before treating the gate as an adversarial trust boundary.

Use protected PRs for changes. Actions are pinned to full commit SHAs, with weekly Dependabot updates. Review dependency changes before merging them.

## Public layout page

The intended GitHub Pages address is https://veteranbv.github.io/creator-micro-ai/. At public launch, configure Pages to deploy from the `main` branch's `/docs` directory. The `.nojekyll` file keeps these static files unprocessed; `index.html` opens `layout.html`, which also works locally. A README link or repository homepage setting does not enable Pages.

Changes publish after they merge into main through the required checks and review. Only public documentation belongs in `/docs`. The page has no analytics or connection to the helper, device or desktop apps. Its gotchas link opens the rendered document on GitHub.

## Publication safety

Publish only project-specific instructions, synthetic fixtures and approved artwork. Private conversation context, unrelated projects, workstation details and personal contact information do not belong in files, commit messages, PRs or build logs. Review context as well as credential patterns; automated checks cannot determine whether every detail was authorized for publication.

Enable **Keep my email addresses private** and **Block command line pushes that expose my email** in GitHub's account email settings. Local Git configuration alone does not control GitHub-generated PR preview commits. Use a GitHub no-reply email for local commits too.

Merge reviewed commits with the rebase method so their checked author identity is preserved. Squash merging is disabled because GitHub can substitute the merging account's email. Inspect the resulting main commit metadata after merging, including the committer identity.

Run `python3 scripts/publication_check.py --all-history` before publication. This checks reachable commits and historical blobs, including author and committer email addresses. CI fetches full history for this check. The approved-domain list is intentionally narrow; review additions rather than adding a private domain just to silence a failure. No credentials are required by the helper or layout.

The offline hostname check uses the [IANA top-level-domain registry](https://data.iana.org/TLD/tlds-alpha-by-domain.txt), saved in `scripts/public-tlds.txt`. Refresh that snapshot during release review. Explicit URL hosts are checked even when their suffix is absent from the snapshot. Exact file and source-expression exceptions require review too.

## Release checklist

- Run all tests and a privacy review of the actual files and Git history being published.
- Finish the physical acceptance matrix on the candidate build and record versions.
- Review the license choice, branding, original artwork and Work Louder attribution.
- Enable private vulnerability reporting, secret scanning/push protection where available and the Codex integration.
- Verify live branch protection and at least one real PR review-gate cycle, including a stale-review failure.
- Upload `assets/social-card.png` as the GitHub social preview.
- Run `python3 scripts/artwork_metadata.py` on changed PNG artwork before committing. This preserves image/color chunks and removes non-rendering metadata. The publication check rejects unsanitized PNGs, including in history.
- Decide whether to distribute source only or acquire Developer ID signing/notarization for binaries. Ad-hoc signing is not notarization.
- Do not publish old troubleshooting history, preferences, diagnostic captures or vendor firmware.

## Public launch

Keep the repository private and the release in draft while preparing publication. Pages can expose a site even while its repository is private, so enabling it is a publication action too.

1. Audit repository files, every published branch/tag and Git identity, PR and issue discussions, Actions logs and artifacts, and the extracted app package. Visibility changes also expose Actions history. Review scanner findings in context; do not publish raw audit captures or local paths.
2. Complete the release checklist above. Record remaining unverified cases explicitly in any pre-release notes; do not present a pre-release as completed stable acceptance.
3. Create a draft pre-release targeting the exact source commit used for its signed ZIP. Attach only that ZIP and `SHA256SUMS`. Download the staged assets again, compare their hashes and verify the extracted app's signature, both architectures, stapled ticket and Gatekeeper assessment. Later documentation commits do not change the binary's source identity.
4. After approval to publish, change repository visibility, enable private vulnerability reporting and secret scanning/push protection where available, and verify that the required checks and administrator protection remain active.
5. Enable Pages from `main` and `/docs`. Wait for a successful deployment, then open the public address without repository authentication. Check all four layers, key highlighting, joystick directions, local assets, mobile layout and external links.
6. Publish the verified pre-release. Check the release page and both downloads without authentication. Recheck Pages, repository protections and the social preview. Do not describe draft assets or an unbuilt Pages site as publicly available.
