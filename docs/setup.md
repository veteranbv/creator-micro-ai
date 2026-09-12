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

## Load the device profile

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

Open the installed Creator Micro AI app, then grant that app Accessibility in System Settings → Privacy & Security → Accessibility. Input Monitoring is not needed by this helper. There is a menu-bar Quit action. To start at login, add the installed app through System Settings → General → Login Items. We do not create a keep-alive daemon that defeats Quit.

Rebuilding an ad-hoc-signed app may invalidate Accessibility trust. If macOS rejects a changed build, remove the stale Accessibility entry and add the installed app again. Do not disable system security features.

## Updating

Quit the helper before updating. Keep a recovery copy of the installed app and your device backup until the new build passes the physical checklist. Move the existing app out of the installation destination before running the installer again. Run only one helper at a time to avoid competing for reserved hotkeys and USB access.

Building, installing and writing the device are separate steps. Rebuilding the helper does not alter the device profile. The helper manages its USB child process; no separate service or network port is needed.
