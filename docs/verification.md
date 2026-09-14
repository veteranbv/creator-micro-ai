# Verification

## Automated checks

Run `bash scripts/test.sh`. The suite checks device mappings, private bridge messages, action-selection fixtures, balanced shortcut construction, publication privacy and review policy. GitHub CI runs on Ubuntu and macOS; only macOS builds the app and runs the Swift tests.

These tests do not launch the helper, post keyboard events, read clipboard data, inspect conversations or modify the device. Passing them does not establish hardware compatibility.

The current review candidate adds fail-closed handling for unreadable approval trees, rejects a control labeled as both approval and denial, prevents superseded app launches from activating, and handles a closed bridge pipe without SIGPIPE termination. Fixtures cover these changes, including a real exited child process. The app-activation check is a source assertion, not a live focus test. These changes have not replaced the physically tested helper below and need a new physical acceptance run before release.

## Wired verification checkpoint

On 2026-09-13, the tester reported that the installed source build completed the wired 1 → 2 → 3 → 4 → 1 cycle, switching both the foreground app and its selected view. The tester then checked all keys across the wired layers and reported that they worked. These are user-reported physical results, not automated test results.

The tested helper executable has SHA-256 `f0fe11ad1e4fe23c299cddd5badf8ef542c075fa01c646a44e84afae0cc5ceb7`. Its installed bundle matched the locally tested build. Both Accessibility and Input Monitoring returned trusted, and the running bridge received the initial device layer after the helper was launched. Re-adding permissions alone does not launch the helper.

The report did not enumerate repetition counts, negative approval cases, disconnect/recovery checks or the full version inventory. Those detailed checks remain pending below. Bluetooth has not been physically verified.

## Detailed physical acceptance checklist

Complete this checklist on the source build you intend to use. Do not mark a row complete from unit tests or results from a different build.

Record macOS, Input, firmware, ChatGPT, Claude and dictation-tool versions; dictation mode and shortcut; keyboard layout; helper commit; and test date. Use synthetic text only. Repeat the dictation checks when changing tools, even if the shortcut stays the same.

| Test | 1 Codex | 2 ChatGPT | 3 Claude Code | 4 Claude Chat |
| --- | --- | --- | --- | --- |
| Layer selects correct foreground view | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Three dictation attempts, one insertion each | Pending | Pending | Pending | Pending |
| New chat, Escape, @, Backspace, Undo, Shift+Return (⇧ ↵), Submit | Pending | Pending | Pending | Pending |
| Search and model picker | Pending | Pending | Pending | Pending |
| Copy latest assistant response, not user/code block | Pending | Pending | Pending | Pending |
| Y allows once, X denies a harmless permission request | Pending | Pending | Pending | Pending |
| Y/X with no request leave KEEP THIS DRAFT untouched | Pending | Pending | Pending | Pending |
| Joystick all eight directions and dial rotation/press | Pending | Pending | Pending | Pending |

Test the full 1 → 2 → 3 → 4 → 1 cycle. Confirm both foreground app and selected view at each step, not just device colors. Record switching separately from action-key acceptance; a passing cycle does not verify dictation, Copy or approvals.

Also test foreground routing with a mismatched layer, rapid layer changes, USB disconnect/reconnect, missing Accessibility permission, missing Input Monitoring permission, repeated Claude copy after hidden toolbar reveal, two- and three-button permission panels, unrelated apps, and quitting/relaunching the helper. Quit must terminate its USB child; no standalone listener or action log should remain.

After replacing an ad-hoc-signed build, check recovery from stale permissions: remove and re-add the installed app in both Accessibility and Input Monitoring, enable both, quit and reopen it, then repeat the full switching cycle. Perform permission changes only with the user's authorization. Do not assume that an enabled permission switch means the current build is trusted.

Check the helper menu while connected, after disconnecting the device, and after reconnecting it. A bridge failure must show the warning icon and recovery guidance; a new ready handshake must restore connected status. Missing Accessibility and missing Input Monitoring must each appear by name, independently of bridge status. A failed workspace switch must not be reported as a disconnected device. “Request sent” is not proof that the expected view is visible.

For ChatGPT approval checks, verify the visible Permissions card with and without its optional approval dropdown. Y must select only Allow once and X only Deny. Neither key may open the dropdown, act on similarly named controls outside the card, or act when more than one permission card is present. Unsupported card structures must do nothing.

Check the interactive reference in a browser too: all four layer buttons, paired key highlighting, the eight joystick directions and the mobile layout.
