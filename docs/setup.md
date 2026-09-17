# Setup

This is a community configuration kit for Work Louder's Creator Micro 2. Install Work Louder's Input app first. This kit does not replace it, flash firmware or bundle vendor code.

## Compatibility boundary

The bridge targets Input 0.18.4 and loads its internal device kit. This is not a stable third-party API; other versions may require adaptation. Run the read-only device check below, then record your Input, firmware and desktop app versions in the [physical acceptance checklist](verification.md).

The current target apps must be installed at `/Applications/ChatGPT.app` and `/Applications/Claude.app`. This ChatGPT desktop build uses bundle ID `com.openai.codex` and includes Chat, Work and Codex tabs. A different product layout or standalone Codex app is not automatically compatible. UI selectors currently assume English labels and `@` assumes a US keyboard layout.

## Configure the applications

1. Set your preferred dictation tool's global start/stop shortcut to Control+Shift+D. Use toggle mode: one tap starts recording and another stops it. Enable insertion into the focused app, then verify that the shortcut works from both desktop apps. This shortcut is the kit's convention, not a universal standard.
2. Verify ChatGPT's default shortcuts in its settings: Control+1 for Chat, Control+3 for Codex, Control+Shift+M for model picker. Remove conflicting custom overrides only after checking what they do. Restart the app if its shortcuts remain stale.
3. Confirm that both desktop apps expose Search and the model picker. The helper uses the apps' controls rather than a universal chat-search keyboard shortcut.

Superwhisper is the maintainer's choice and the dictation tool used in testing, not a required dependency. Test alternatives across all four workspaces before relying on them. A tool that only supports hold-to-talk, opens its own editor, or requires manual pasting needs additional configuration and is not a drop-in replacement for this profile.

## Install a signed download

1. Open [GitHub Releases](https://github.com/veteranbv/creator-micro-ai/releases) and read the pre-release's compatibility and verification limits.
2. Download the attached `Creator-Micro-AI-...zip` and `SHA256SUMS`. GitHub's **Source code** archives do not contain the built app. If no release is published, use the source-build instructions below.
3. Extract the ZIP in Finder. Move **Creator Micro AI.app** into Applications before opening it. Either your user Applications folder or `/Applications` is supported. Keep only one active installation, at the same location for future updates.
4. Open that installed copy and follow **Setup & Status**. Grant Accessibility and Input Monitoring to the same copy when prompted. The app cannot grant those permissions itself.

The maintainer's release ZIP is Developer ID-signed and notarized. macOS still controls its first-open confirmation and privacy permissions. Do not disable Gatekeeper or remove quarantine to bypass a warning. If macOS rejects the download, stop and report the version and warning without private diagnostic data.

For an optional checksum check, place both downloaded files in one folder, open Terminal in that folder and run `shasum -a 256 -c SHA256SUMS`. The result must say `OK`. This detects a changed download; it does not replace macOS signature checks or your physical tests.

For an update, quit the running helper, keep a recovery copy outside the installation location, and replace the app at that same location. Keep existing permission grants untouched initially, then check both statuses and test switching. Refresh both grants only if trust fails. Do not rewrite a matching device profile simply to update the helper.

## Guided setup

Open the installed Creator Micro AI app. Setup opens on the first run of a build and resumes if you close it partway through. You can reopen it from Applications at any time, or choose **Setup & Status** from its menu-bar icon. You do not need to find that icon to continue setup.

Install a signed download as described above, or use the source-build installation below. Downloading or building alone does not install the helper. Keep the installed app in one location when granting permissions.

1. **Your apps:** checks that this helper is installed in Applications, plus the supported Input version and the two desktop apps. Nothing is downloaded or installed silently. **Show this helper in Finder** identifies the exact copy to move or add to permission lists.
2. **Permissions:** explains Accessibility and Input Monitoring separately, opens each settings pane, and checks this running helper's trust. Add the same installed app in both lists. macOS, not the wizard, handles password or Touch ID prompts. Use **Restart helper after permission changes** when needed.
3. **Your device:** connect exactly one device by USB and close Input's configuration window. Choose **Check existing profile** first. A matching profile needs no rewrite. Applying or restoring requires a separate confirmation and pauses the helper bridge so it cannot compete for the connection. Applying backs up the current keymap before writing and verifies readback.
4. **Dictation:** configure Control+Shift+D in your chosen tool and confirm a short disposable-draft test.
5. **Try it:** confirm the physical layer and key tests yourself. Bluetooth is optional and is labeled untested unless you confirm it. After a disconnect, recheck the profile over USB before finishing.
6. **Ready:** shows current checks alongside your confirmations. It cannot finish with missing permissions, a disconnected bridge or an unchecked profile. Closing the window leaves the helper running.

The matching control reference is included in the app and opens locally in your browser. No web connection is needed for the reference. Setup help remains available on every screen.

Saved progress is not proof that the device or permissions still work. Reopening the helper requires a fresh profile check. A changed build also clears physical test confirmations. See [PRIVACY.md](../PRIVACY.md) for the small amount of local setup state retained.

If a profile write fails or times out, it may be incomplete. Keep USB connected, choose **Show recovery copies**, then **Restore a saved profile**. The recovery file stays private. Restart Input after a successful write to refresh cached labels. Never rewrite a working profile solely because permission switches appear enabled but app switching fails.

## Command-line profile setup

The wizard and these commands use the same profile configurator. The commands remain available for development and recovery.

Quit any running copy of the helper first. The profile operation must not compete with the helper's USB connection.

```sh
bash scripts/device.sh --check
```

This reads the device and validates the keymap schema. It does not certify the entire firmware version. Applying **replaces all existing device profiles, macros, lighting and linked-app configuration** with the supplied four-layer profile. A recovery copy is written before the first device write.

```sh
bash scripts/device.sh --apply
```

The tool rereads the file to verify the write. If it fails or times out, do not assume the device was unchanged. Restore the reported recovery copy with `bash scripts/device.sh --restore /absolute/path/to/keymap.before.json`. Restore validates that backup and can replace a damaged or unreadable current keymap. If the current file can be read, it is saved before replacement; otherwise no new recovery copy is possible. Keep backups private. Restart Input after a successful write so its radial labels refresh. If Input later overwrites the profile from stale local state, stop and recheck the on-device configuration.

## Build and install the helper

```sh
bash scripts/test.sh
python3 scripts/install.py
```

Installation copies the source-built app into your user Applications directory. It refuses to overwrite an existing installation or proceed while a conflicting helper is running. It does not launch the app or silently grant permissions.

Open the installed Creator Micro AI app and configure these separate permissions in System Settings → Privacy & Security:

1. In Accessibility, add and enable the installed Creator Micro AI app. The helper uses this permission to control supported apps.
2. In Input Monitoring, add and enable the same installed app. The Input-based USB bridge requires this permission in the tested setup. macOS attributes the child process's device access to Creator Micro AI.
3. Quit and reopen Creator Micro AI after changing permissions.

Keep one entry for the installed helper in each permission list, not multiple entries in Accessibility. Input Monitoring grants broad keyboard-input access, even while other apps are active. This helper does not record typing; see [PRIVACY.md](../PRIVACY.md) for its actual behavior and vendor boundary.

The menu-bar icon becomes a warning triangle when the helper needs attention. Open its menu to check device connection, Accessibility, Input Monitoring and workspace-switch status. The helper checks both permissions through macOS without recording input. A bridge failure still lists connection checks because permission is not the only possible cause. “Request sent” means the helper delivered the switch request, not that it independently verified the resulting view. Status stays in memory; it is not an action log.

There is a menu-bar Quit action. To start at login, add the installed app through System Settings → General → Login Items. We do not create a keep-alive daemon that defeats Quit.

Rebuilding an ad-hoc-signed app may invalidate Accessibility or Input Monitoring trust. An enabled switch can still refer to an older build. After replacing the installed build, refresh both entries together:

1. Remove Creator Micro AI from Accessibility and add the installed copy again.
2. Enable its Accessibility switch.
3. Remove Creator Micro AI from Input Monitoring and add the same installed copy again.
4. Enable its Input Monitoring switch.
5. Quit and reopen Creator Micro AI.
6. Check that its menu reports both permissions trusted and the device bridge connected.

Do not disable system security features.

Verify the complete physical cycle: 1 → 2 → 3 → 4 → 1. Every transition must select the expected app and view. Device color changes alone do not prove that the bridge is connected. If colors change but no app or view changes, check Input Monitoring as well as Accessibility before rewriting the device profile.

## Bluetooth operation

On a Bluetooth-capable device, complete the wired setup first. Disconnect USB and connect the device to this Mac over Bluetooth. Leave the same installed helper running; the tested transition did not require a separate helper, profile or permission reset.

Check that the helper reports both permissions trusted and the device bridge connected. With USB still unplugged, test 1 → 2 → 3 → 4 → 1 and all keys across the layers. Then turn the device off and on, let Bluetooth reconnect, and repeat the cycle.

These checks have user-reported passes on the build in the [verification record](verification.md). Continue using USB for profile configuration: writing the profile over Bluetooth has not been tested. Simultaneous USB/Bluetooth connections, multiple devices and sleep/wake recovery are also unverified.

## Updating

Quit the helper before updating. Keep a recovery copy of the installed app and your device backup until the new build passes the physical checklist. Move the existing app out of the installation destination before running the installer again. Run only one helper at a time to avoid competing for reserved hotkeys and USB access.

Building, installing and writing the device are separate steps. Rebuilding the helper does not alter the device profile. The helper manages its USB child process; no separate service or network port is needed.
