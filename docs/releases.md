# Local signed releases

GitHub runs credential-free tests and reviews. Signing runs on a trusted Mac,
not a GitHub runner. The release command uses an existing Developer ID Application
key and saved notarization credentials. It never exports keys, imports certificates,
installs the helper or publishes a GitHub release. If needed, it adds the signing
keychain to the search list only for signing, then restores the original list even
on signing failure. Do not change keychain settings or run another signing process
concurrently. Forced termination can prevent cleanup; check the search list after
force-quitting a release during signing.

## One-time preparation

Use the normal development prerequisites plus an Apple Developer membership and
a Developer ID Application identity in a dedicated local keychain. Keep its recovery
copy in your password manager. This ZIP distribution does not need an Installer
certificate. Unlock the keychain locally before running a release. Do not put its
password in command history, repository files or GitHub secrets.

For automated local builds, you can instead supply `CREATOR_SIGNING_PASSWORD`
through a secret manager. Use this only with a dedicated release keychain: the
command unlocks it only for signing, then locks it on success, failure or
interruption, even if it was already unlocked. Tests, compilation and notarization
run outside that unlock window. The password must be nonempty, single-line and no
more than 128 UTF-8 bytes, matching the macOS password prompt limit. Forced termination
can prevent cleanup; lock the dedicated keychain yourself after force-quitting.

For example, put only a secret reference in an ignored `private/.env`:

```dotenv
CREATOR_SIGNING_PASSWORD=op://YOUR_VAULT/YOUR_SIGNING_ITEM/keychain-password
```

Authenticate the 1Password CLI using your existing account or service-account
setup outside this checkout. Then run:

```sh
op run --env-file private/.env -- python3 scripts/release.py --revision FULL_REVIEWED_COMMIT_SHA
```

The release command sends the password through a private stdin pipe to the
macOS keychain tool, not a command argument. It passes only a small environment
allowlist to build, test and signing tools. Your existing PATH is preserved without
rewriting it, even for child processes. System utilities use absolute paths. The
compiler and its external tools come from the system-selected Xcode installation.
Release children do not receive `DEVELOPER_DIR`, `SDKROOT` or `TOOLCHAINS` overrides.
This does not change the global Xcode selection or ordinary development overrides.
The full test suite uses the configured absolute Node path and the same Python
interpreter that launched the release. Use a trusted Python 3.10 or newer and verify
the configured Node installation locally. The signing Mac must also provide the
system JSON test tool at `/usr/bin/jq`. Missing tools stop the release; it does not
fall back to similarly named tools on PATH. No shell startup files are edited.
The release checkout must have complete, non-shallow history and must not contain
Git replacement references. Source checks
and export also disable object replacement to preserve the reviewed commit's bytes.
Tests run in a fresh temporary Git checkout of the reviewed revision, without the
original checkout's ignored bytecode caches, local modules or build outputs.
The temporary checkout fetches all local Git refs, including custom and remote-tracking
refs, so the publication and ancestry tests retain the original history coverage.
It checks that every original ref and object ID is present after the fetch.
Hidden or changed refs stop the release instead of narrowing the audit; the command
does not change ref-visibility settings or deepen shallow history automatically.
Before and after tests, both checkouts' regular-file bytes and executable modes
must match the reviewed tree. Index flags that hide changes (`assume-unchanged`
or `skip-worktree`) are rejected. A clean Git status alone is not enough; filters
or line-ending conversion must not change the files that the suite actually tests.
Before extraction or compilation, the source archive's file paths and Git blob IDs
must match the reviewed tree. Missing, added, duplicate or rewritten files stop the
release, including changes caused by local or configured Git export attributes.
No Git attributes or user settings are changed by this check.
1Password tokens and unrelated environment secrets are not forwarded. This
automation does not change private-key access rules. During one-time setup,
authorize the system codesign tool for this identity; do not allow all applications.

Save notarization credentials interactively with `xcrun notarytool store-credentials`.
Use its secure prompt, not a password argument. Run `xcrun notarytool store-credentials --help`
for the installed tool's options. The release command uses only the saved profile name.

Create an ignored `private/release.json` file on the signing Mac:

```json
{
  "identity": "CERTIFICATE_SHA1_FINGERPRINT",
  "team_id": "APPLE_TEAM_ID",
  "keychain": "~/Library/Keychains/release.keychain-db",
  "notary_profile": "release-notary",
  "node": "/absolute/path/to/trusted/node"
}
```

Replace the placeholders with your local values. Find the certificate fingerprint
using `security find-identity -v -p codesigning` with your keychain path.
The identity must be Developer ID Application, not an ad-hoc or development identity.
If the notarization profile is in a separate keychain, add `notary_keychain` with its
path. Set `node` to your verified Node 22 or newer executable. Its absolute path is
local configuration, not a path to copy from another Mac. Existing release settings
need this field before their next build. Do not add passwords or API keys to this
file. Unknown fields are rejected.

Your certificate's developer name and team identifier are public in a signed app.
The private key and notarization credentials remain in local keychains. Notarization
uploads the signed app to Apple; no source checkout or local settings are packaged.

## Build a release

Finish review and CI first. Check out the approved commit with a clean working tree,
then run:

```sh
python3 scripts/release.py --revision FULL_REVIEWED_COMMIT_SHA
```

The command checks credentials, runs the full test suite in its isolated checkout,
exports that exact commit, and builds both arm64 and x86_64 slices. It signs with hardened runtime and a secure
timestamp, verifies the team and bundle identity, waits for Apple's acceptance,
staples the ticket, and creates a new ZIP. It extracts that ZIP and checks its
signature, architectures, stapled ticket and Gatekeeper acceptance before making
the release directory available under `build/releases/`.

Each directory contains only the ZIP and SHA256SUMS. Existing releases are never
overwritten. Temporary source and submission files are removed on normal exit or
failure. A forced process termination can leave temporary files under the ignored
build directory; these contain no exported keys. Do not upload the entire build folder.

Release ZIPs omit resource forks, extended attributes and local ACLs. The signed
app files and stapled ticket remain intact and are verified after extraction.
This packaging choice does not bypass quarantine applied to a new download.
App builds include `LICENSE` and `NOTICE.md` in their resources before signing.
For an already signed candidate that predates this packaging rule, include those
two files from its exact source revision beside the unchanged app in the release
ZIP. Preserve the original archive, recompute `SHA256SUMS` for the distribution
archive, and repeat extracted-download verification. Record that packaging-only
change in the release notes. Never add files inside an already signed app.

Failures report the failed stage without printing account details or raw tool output.
Cancellation or timeout kills the active command's process group and waits for the
child to finish before keychain or temporary-file cleanup begins.
If notarization fails or times out, inspect `xcrun notarytool history` locally using
your saved profile. Apple may continue processing a submission after a timeout.
Do not publish a rejected or unverified artifact.

## Acceptance before publishing

Notarization is not a hardware test. Install and test the signed candidate only with
the user's approval. Verify the full USB and Bluetooth matrix, including the bridge
child process under hardened runtime. Test a second signed update to confirm that
Accessibility and Input Monitoring remain granted. The first migration from ad-hoc
signing may require removing and re-adding the app in both permission lists.

Keep the bundle identifier and Developer ID team stable across updates. Do not promise
that macOS can never request consent again. Only publish the ZIP and its checksum
after recording the candidate's physical verification separately.
