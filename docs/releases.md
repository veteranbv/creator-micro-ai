# Local signed releases

GitHub runs credential-free tests and reviews. Signing runs on a trusted Mac,
not a GitHub runner. The release command uses an existing Developer ID Application
key and saved notarization credentials. It never exports keys, imports certificates,
changes the keychain search list, installs the helper or publishes a GitHub release.

## One-time preparation

Use the normal development prerequisites plus an Apple Developer membership and
a Developer ID Application identity in a dedicated local keychain. Keep its recovery
copy in your password manager. This ZIP distribution does not need an Installer
certificate. Unlock the keychain locally before running a release. Do not put its
password in command history, repository files or GitHub secrets.

Save notarization credentials interactively with `xcrun notarytool store-credentials`.
Use its secure prompt, not a password argument. Run `xcrun notarytool store-credentials --help`
for the installed tool's options. The release command uses only the saved profile name.

Create an ignored `private/release.json` file on the signing Mac:

```json
{
  "identity": "CERTIFICATE_SHA1_FINGERPRINT",
  "team_id": "APPLE_TEAM_ID",
  "keychain": "~/Library/Keychains/release.keychain-db",
  "notary_profile": "release-notary"
}
```

Replace the placeholders with your local values. Find the certificate fingerprint
using `security find-identity -v -p codesigning` with your keychain path.
The identity must be Developer ID Application, not an ad-hoc or development identity.
If the notarization profile is in a separate keychain, add `notary_keychain` with its
path. Do not add passwords or API keys to this file. Unknown fields are rejected.

Your certificate's developer name and team identifier are public in a signed app.
The private key and notarization credentials remain in local keychains. Notarization
uploads the signed app to Apple; no source checkout or local settings are packaged.

## Build a release

Finish review and CI first. Check out the approved commit with a clean working tree,
then run:

```sh
python3 scripts/release.py --revision FULL_REVIEWED_COMMIT_SHA
```

The command checks credentials, runs the full test suite, exports that exact commit,
and builds both arm64 and x86_64 slices. It signs with hardened runtime and a secure
timestamp, verifies the team and bundle identity, waits for Apple's acceptance,
staples the ticket, and creates a new ZIP. It extracts that ZIP and checks its
signature, architectures, stapled ticket and Gatekeeper acceptance before making
the release directory available under `build/releases/`.

Each directory contains only the ZIP and SHA256SUMS. Existing releases are never
overwritten. Temporary source and submission files are removed on normal exit or
failure. A forced process termination can leave temporary files under the ignored
build directory; these contain no exported keys. Do not upload the entire build folder.

Failures report the failed stage without printing account details or raw tool output.
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
