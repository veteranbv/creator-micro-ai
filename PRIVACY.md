# Privacy

## What the helper uses

- The selected device layer, checked roughly every 750 ms through Work Louder's installed device kit.
- The foreground app's process identity. Only the two supported desktop apps are action targets.
- Accessibility roles, control labels, selected radio state, parent/child relationships and specific structural classes. Labels may contain message excerpts. This access is transient, in memory, and used to find the requested control.
- Five reserved Control+Option+Command+F13 through F17 hotkeys. This is shortcut registration, not a listener for general typing.

It sends balanced app-switch shortcuts and presses matching accessibility controls. Copy response asks the app to copy; the helper never reads the resulting clipboard. The joystick's ordinary copy/paste/select-all shortcuts come from the device itself.

## macOS permissions

Accessibility allows the helper to inspect and control supported apps. The tested Input-based USB bridge also requires Input Monitoring for the helper app. macOS can attribute a child process's access request to its parent app, so Input's own permission entry does not replace Creator Micro AI's entry.

Input Monitoring grants broad access to keyboard input, not a device-only permission. The kit uses the bridge to query device state, not to record typing. Granting this permission does not limit the vendor library to this project's intended use; the third-party boundary below still applies.

## What this code does not collect

No typed-text recording, clipboard reads, audio capture, screenshots, conversation exports, URL history, telemetry or action-history logs. There is no runtime log switch. The helper does not listen on TCP or open an HTTP endpoint. Its child process receives only a small environment allowlist and communicates through inherited pipes. Vendor exceptions are replaced with fixed protocol failures, never forwarded verbatim.

## Files and third parties

Setup saves its current step and your explicit test confirmations in this app's macOS preferences. A fingerprint of the helper executable ties confirmations to the build you tested. These preferences stay on this Mac. Permissions, connection state and profile-match results are checked again, not restored as trusted from saved progress. Setup does not record the test actions or text you enter.

Explicit device configuration writes a recovery copy under your user Library's `Application Support/Creator Micro AI/backups`, in a private directory. A backup may contain your prior custom macros or paths. Never commit or upload it. It is retained until you deliberately remove it. The setup window holds the latest recovery location in memory and can reveal it in Finder. Neither setup nor the normal helper runtime creates an action log.

The helper loads Work Louder's device kit from your Input installation. We do not redistribute or claim to audit the entire vendor app. macOS itself may retain crash and security diagnostics. Your chosen dictation tool, Input, ChatGPT and Claude have separate data handling and network behavior. Choosing a different dictation tool does not change what this helper collects, but can change where your audio and transcript are processed.

## Reporting a bug

Start with versions, the failing action and whether it beeps. Use synthetic text. Do not attach raw accessibility trees, preferences, browser profiles, secrets, clipboard dumps or recordings. The automated privacy scan is a guardrail, not proof that every possible sensitive file has been detected.
