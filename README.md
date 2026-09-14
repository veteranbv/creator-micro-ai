# Creator Micro AI

**A fan-made configuration kit for Work Louder's Creator Micro 2.**

![Creator Micro AI](assets/social-card.png)

Work Louder built a fantastic tactile platform. This project builds on it: a shared set of controls for talking to AI, navigating conversations, approving individual actions and switching between desktop workspaces. It is a configuration and companion-helper project, not replacement firmware or a replacement for Input.

Start with the [Creator Micro 2 from Work Louder](https://worklouder.cc/creator-micro-2). You still need the hardware and Work Louder's Input app. This is an independent enthusiast project, not an official, sponsored or endorsed Work Louder release. Vendor names belong to their respective owners. This kit does not distribute firmware or Input software.

## Four layers, one muscle memory

| Layer | Workspace brought forward |
| --- | --- |
| 1 | Codex inside ChatGPT desktop |
| 2 | Chat inside ChatGPT desktop |
| 3 | Code inside Claude desktop |
| 4 | Chat inside Claude desktop |

These are desktop views, not the Codex CLI or Claude Code CLI. A standalone Codex app is not a tested target. Desktop updates can change the shortcuts and accessibility labels this helper relies on.

The wide key sends Control+Shift+D to your configured dictation tool. The key beside it submits. Other keys keep the same jobs on every layer: context `@`, Backspace, Undo, model picker, Copy response, Allow once, Deny and Shift+Return (⇧ ↵). Turn the dial for arrow navigation; press it for search.

**Actions follow the foreground app, not the layer.** Changing layers switches the app/view. If you then click into another supported app, Copy response and approval keys act there. They do not drag you back to the layer's app.

See the [interactive side-by-side layout](https://veteranbv.github.io/creator-micro-ai/), [setup guide](docs/setup.md), [gotchas](docs/gotchas.md), and [physical test checklist](docs/verification.md).

### The physical layout

![Illustrated Creator Micro keycaps beside their matching actions](docs/assets/layout-reference.svg)

The real device, shown separately for reference:

![Creator Micro 2 with the installed pencil, hand, chain, back arrow, undo, model, copy, Y and X caps, a clear Shift+Return key, a wide clear dictation bar and a submit arrow](docs/assets/creator-micro-device.png)

USB cable at the top. The interactive reference pairs these exact key positions with their actions. The wide clear bar is dictation; the clear key above Submit is labeled ⇧ ↵. It sends Shift+Return: a newline in supported composers, or activation of a focused control if the app accepts that shortcut. Submit sends plain Return.

## Choose your dictation tool

Configure your preferred dictation tool to use Control+Shift+D as its global start/stop shortcut. This is the kit's recommended convention, not a universal standard. The tool needs to start recording on one tap, stop on another, and insert the result into the focused app.

Superwhisper is my choice for this setup and the tool used in dictation testing. The kit does not call Superwhisper directly or require it to be installed. Other tools need their own verification across the four workspaces. A hold-to-talk-only tool is not a direct match for this tap-to-toggle profile.

## Status

This is a pre-release, source-built kit. Automated tests cover the profile, action-selection rules, shortcut construction and privacy checks. USB and Bluetooth four-layer switching and all controls have passed user-reported checks on the source build recorded in the [verification checklist](docs/verification.md). Detailed failure/recovery and compatibility checks remain pending.

## Build and test

Use macOS with Xcode Command Line Tools, Node 22 or newer for development tests, and Python 3.10 or newer. No npm install, API key, cloud service or paid AI account is required to build this helper. Target apps and dictation services have their own requirements.

```sh
bash scripts/test.sh
bash scripts/build.sh
```

The build creates `build/Creator Micro AI.app` without launching it, altering Accessibility permissions or writing the device. Source builds use ad-hoc signing. They are not notarized downloads.

## Privacy first

No keystroke recorder, clipboard reader, audio recorder, analytics, background upload or runtime action log. The helper registers only five reserved controller shortcuts and examines supported apps' accessibility controls in memory. Some accessibility labels can contain conversation text; those labels are not persisted or transmitted. The USB bridge communicates through private inherited pipes, not a listening network port.

Your chosen dictation tool and the AI apps process your voice/text separately under their own settings. This project does not make those services offline or change their privacy policies. Read [PRIVACY.md](PRIVACY.md).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [repository administration](docs/repository-admin.md) for tests, Codex review, branch protection and publication checks.
