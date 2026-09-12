# Verification

## Automated checks

Run `bash scripts/test.sh`. The suite checks device mappings, private bridge messages, action-selection fixtures, balanced shortcut construction, publication privacy and review policy. GitHub CI runs on Ubuntu and macOS; only macOS builds the app and runs the Swift tests.

These tests do not launch the helper, post keyboard events, read clipboard data, inspect conversations or modify the device. Passing them does not establish hardware compatibility.

## Physical acceptance: pending

Complete this checklist on the source build you intend to use. Do not mark a row complete from unit tests or results from a different build.

Record macOS, Input, firmware, ChatGPT and Claude versions; keyboard layout; helper commit; and test date. Use synthetic text only.

| Test | 1 Codex | 2 ChatGPT | 3 Claude Code | 4 Claude Chat |
| --- | --- | --- | --- | --- |
| Layer selects correct foreground view | Pending | Pending | Pending | Pending |
| Three dictation attempts, one insertion each | Pending | Pending | Pending | Pending |
| New chat, Escape, @, Backspace, Undo, Newline / Enter, Submit | Pending | Pending | Pending | Pending |
| Search and model picker | Pending | Pending | Pending | Pending |
| Copy latest assistant response, not user/code block | Pending | Pending | Pending | Pending |
| Y allows once, X denies a harmless permission request | Pending | Pending | Pending | Pending |
| Y/X with no request leave KEEP THIS DRAFT untouched | Pending | Pending | Pending | Pending |
| Joystick all eight directions and dial rotation/press | Pending | Pending | Pending | Pending |

Also test foreground routing with a mismatched layer, rapid layer changes, USB disconnect/reconnect, missing Accessibility permission, repeated Claude copy after hidden toolbar reveal, two- and three-button permission panels, unrelated apps, and quitting/relaunching the helper. Quit must terminate its USB child; no standalone listener or action log should remain.

Check the interactive reference in a browser too: all four layer buttons, paired key highlighting, the eight joystick directions and the mobile layout.
