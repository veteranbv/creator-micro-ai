# Verification

## Automated checks

Run `bash scripts/test.sh`. The suite checks device mappings, private bridge messages, action-selection fixtures, balanced shortcut construction, publication privacy and review policy. GitHub CI runs on Ubuntu and macOS; only macOS builds the app and runs the Swift tests.

These tests do not launch the helper, post keyboard events, read clipboard data, inspect conversations or modify the device. Passing them does not establish hardware compatibility.

The review candidate adds fail-closed handling for unreadable approval trees, rejects a control labeled as both approval and denial, prevents superseded app launches from activating, and handles a closed bridge pipe without SIGPIPE termination. Fixtures cover these changes, including a real exited child process. The app-activation regression is a source assertion; rapid-launch race conditions were not independently tested live.

Further review requires every nonempty approval label to identify the same permitted action and aborts Copy when a response tree is unreadable, including Claude toolbar retries. Permission-container attribute errors and incomplete workspace child reads also abort selection. These error cases have synthetic coverage. Normal operation on the updated build was physically tested as recorded below.

## Current USB and Bluetooth acceptance

On 2026-09-14, the tester confirmed successful operation over both USB and Bluetooth on source commit `ed16b6395ee9137750810e1d7a3f4e409bb68b5f`. The confirmation covered the full four-layer app/view cycle and all controls, including Copy response, Y/X approvals, dictation and all joystick directions. These are user-reported physical results, not automated observations.

After icon-metadata cleanup and rebase merging, the reachable source-equivalent revision is `5e6682579528fd95e0241d589b872a20c1527a90`. Only `assets/AppIcon.icns` metadata differs from the original snapshot. The test report and executable hash below identify the original installed build, not a new physical test of the rewritten revision.

The installed bundle was verified identical to the build that passed `bash scripts/test.sh`. Its executable SHA-256 is `f9a78d22574612bc1e3a3497c73064a68d871357d353c9a9b8abdfd76c786d8a`. The previous working app was retained privately for recovery. Installation did not rewrite the device profile.

This confirms normal operation on the tested setup, not every failure mode. Exact repetition counts, deliberately missing permissions, multiple simultaneous approval cards, rapid focus changes during approval, and the full version inventory were not separately reported. New runtime fixes after this commit require their own acceptance check; later documentation-only commits do not change the tested executable.

The subsequent review candidate also aborts workspace and action selection on unreadable labels, requires complete trees for model/search controls, and binds delayed approvals to the original focused window and control. Injected accessibility fixtures cover label and tree failures. Source assertions verify the delayed approval guards; live same-process window switching during the delay is not yet verified. This candidate is built separately and has not replaced the accepted installation above.

The candidate resumes an interrupted layer activation after bridge recovery, with synthetic state-transition coverage. The fixed ChatGPT model shortcut no longer traverses conversation contents; its ordering has source-assertion coverage. The build checks that the executable's minimum macOS version matches the manifest. Compiling for macOS 13 does not establish a successful live launch on that OS.

## Wired verification checkpoint

On 2026-09-13, the tester reported that the installed source build completed the wired 1 → 2 → 3 → 4 → 1 cycle, switching both the foreground app and its selected view. The tester then checked all keys across the wired layers and reported that they worked. These are user-reported physical results, not automated test results.

The tested helper executable has SHA-256 `f0fe11ad1e4fe23c299cddd5badf8ef542c075fa01c646a44e84afae0cc5ceb7`. Its installed bundle matched the locally tested build. Both Accessibility and Input Monitoring returned trusted, and the running bridge received the initial device layer after the helper was launched. Re-adding permissions alone does not launch the helper.

This earlier report did not enumerate repetition counts, negative approval cases, disconnect/recovery checks or the full version inventory. The current acceptance record above supersedes its normal-operation coverage.

## Bluetooth verification checkpoint

On 2026-09-13, the tester disconnected USB, connected the device over Bluetooth and reported that the four-layer app/view cycle worked. After being asked to check all keys across the layers and repeat the cycle after a device power-off/on and Bluetooth reconnection, the tester reported that everything worked.

This used the same installed helper executable identified above, from source checkpoint `94ae0a3abae72263abe46a607a8f44d5b38e46c9`. No Bluetooth-specific code, profile write, helper replacement or permission change was needed. A runtime check after the transport change found both permissions trusted and device-ready state present. Key behavior and the power-cycle/reconnect result are user-reported, not independently instrumented.

The reachable source-equivalent revision after icon-metadata cleanup is `8e8dc0ad5aee80966f0646fb8a52ddb2b162c9cb`. This checkpoint is retained on main after rebase merging. Only `assets/AppIcon.icns` metadata differs from that original snapshot; the source files are identical. The historical test still refers to the original installed build.

These results cover the tested device and setup. They do not establish wireless profile writing, simultaneous USB/Bluetooth connections, multiple devices, sleep/wake recovery or compatibility with other firmware and app versions. The detailed negative cases and version inventory below remain incomplete.

## Detailed physical acceptance checklist

Complete this checklist on the source build you intend to use. Do not mark a row complete from unit tests or results from a different build.

Record macOS, Input, firmware, ChatGPT, Claude and dictation-tool versions; dictation mode and shortcut; keyboard layout; helper commit; and test date. Use synthetic text only. Repeat the dictation checks when changing tools, even if the shortcut stays the same.

| Test | 1 Codex | 2 ChatGPT | 3 Claude Code | 4 Claude Chat |
| --- | --- | --- | --- | --- |
| Layer selects correct foreground view | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Dictation start/stop and insertion | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| New chat, Escape, @, Backspace, Undo, Shift+Return (⇧ ↵), Submit | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Search and model picker | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Copy response | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Y allows once, X denies a permission request | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Y/X with no request leave KEEP THIS DRAFT untouched | Pending | Pending | Pending | Pending |
| Joystick all eight directions and dial rotation/press | User-reported pass | User-reported pass | User-reported pass | User-reported pass |

The pass entries refer to the current acceptance commit above on both transports. Three consecutive dictation attempts with exactly one insertion each, and Copy discrimination between assistant responses, user text and code blocks, still need explicit results.

Test the full 1 → 2 → 3 → 4 → 1 cycle. Confirm both foreground app and selected view at each step, not just device colors. Record switching separately from action-key acceptance; a passing cycle does not verify dictation, Copy or approvals.

Also test foreground routing with a mismatched layer, rapid layer changes, USB disconnect/reconnect, missing Accessibility permission, missing Input Monitoring permission, repeated Claude copy after hidden toolbar reveal, two- and three-button permission panels, unrelated apps, and quitting/relaunching the helper. Quit must terminate its USB child; no standalone listener or action log should remain.

After replacing an ad-hoc-signed build, check recovery from stale permissions: remove and re-add the installed app in both Accessibility and Input Monitoring, enable both, quit and reopen it, then repeat the full switching cycle. Perform permission changes only with the user's authorization. Do not assume that an enabled permission switch means the current build is trusted.

Check the helper menu while connected, after disconnecting the device, and after reconnecting it. A bridge failure must show the warning icon and recovery guidance; a new ready handshake must restore connected status. Missing Accessibility and missing Input Monitoring must each appear by name, independently of bridge status. A failed workspace switch must not be reported as a disconnected device. “Request sent” is not proof that the expected view is visible.

For ChatGPT approval checks, verify the visible Permissions card with and without its optional approval dropdown. Y must select only Allow once and X only Deny. Neither key may open the dropdown, act on similarly named controls outside the card, or act when more than one permission card is present. Unsupported card structures must do nothing.

Check the interactive reference in a browser too: all four layer buttons, paired key highlighting, the eight joystick directions and the mobile layout.
