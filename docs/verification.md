# Verification

## Short candidate test plan

Use the signed candidate identified by the maintainer, not an older installed build. Keep the device profile and both permission grants unchanged for the update test. Use synthetic text and harmless read-only approval requests. Stop and report any unexpected submission, Always allow selection, duplicate dictation or crash.

1. **Update and status.** Open Creator Micro AI from Applications. In Setup & Status, check that Accessibility and Input Monitoring are trusted and the device bridge is connected. Record any permission prompt before changing settings.
2. **USB controls.** With setup open, cycle 1 → 2 → 3 → 4 → 1 twice. Confirm the foreground app and view, not only the device color. In each layer, test dictation three times, Copy response, search/model controls, editing keys, all eight joystick directions and the dial. Each dictation attempt must insert exactly once. Copy response must select the assistant response, not your message or a code-block-only copy.
3. **Approval safety.** In each layer, enter `KEEP THIS DRAFT`, then press Y and X with no approval visible. The draft must remain unchanged and unsent. Use two harmless permission requests to test Y allows once and X denies. Test both available approval layouts. Switch to another window before pressing an approval key; it must not approve a request in the old window. If a case cannot be arranged, report it as not tested.
4. **Bluetooth controls.** Disconnect USB, connect Bluetooth, and repeat steps 2 and 3. Do not rewrite the profile over Bluetooth.
5. **Reconnect and sleep.** On each connection type, disconnect or power off the device, reconnect, wait up to 40 seconds, and try the layer cycle. Repeat three times. Sleep and wake the Mac, then try again. If a crash dialog appears, do not click Reopen before checking recovery.
6. **Apps and helper.** Quit and reopen each target app, then test its two layers. Quit Creator Micro AI from its menu and reopen it from Applications. Check status and switching. Permission-removal tests are coordinated separately so only this helper's two grants are changed and restored.
7. **Normal use.** Use this same build for two working days, including sleep/wake and USB/Bluetooth changes. Report crashes, hangs, repeated permission prompts or unexpected actions. This is an acceptance target, not a completed test.

Reply with the candidate version/build, USB pass/fail, Bluetooth pass/fail, approval safety pass/fail, reconnect/sleep pass/fail, and anything skipped. For failures, give the step, connection type and what happened. Do not post raw diagnostic reports or private conversation screenshots publicly.

Only one Mac is available for this acceptance run. Second-machine testing is unavailable. Universal compilation is not proof of Intel hardware compatibility or support for other macOS versions. Record the tested OS and app versions, and keep broader compatibility unverified.

## Bridge reliability investigation

A native HID device-open crash was reported during extended use with Input 0.18.4. Switching worked after the user clicked Reopen; this does not demonstrate automatic recovery. The exact cause of that crash remains unconfirmed.

The candidate isolates failed native connections by exiting the bridge child instead of reopening another handle in that process. Parent restart delays cannot be bypassed by status refreshes. Repeated failures back off to 30 seconds and reset only after a ready connection lasts 30 seconds. Current status distinguishes signal termination, connection restart and launch failure without recording raw errors or action history.

Automated coverage includes JavaScript failure paths and real synthetic subprocesses for signal termination, automatic restart, ready messages, capped retry timing, setup pause/resume and shutdown. These tests do not load vendor code or access hardware. Candidate hardware recovery and sustained-use acceptance remain pending; do not mark the reported native crash resolved from these fixtures alone.

## Automated checks

Run `bash scripts/test.sh`. The suite checks device mappings, private bridge messages, action-selection fixtures, balanced shortcut construction, publication privacy and review policy. GitHub CI runs on Ubuntu and macOS; only macOS builds the app and runs the Swift tests.

These tests do not launch the helper, post keyboard events, read clipboard data, inspect conversations or modify the device. Passing them does not establish hardware compatibility.

Setup fixtures cover step gating, build-scoped confirmations, malformed operation messages, private recovery paths and readback failures. On macOS, an isolated AppKit fixture renders all seven screens and asserts layout, column width and scrolling. A separate lifecycle run waits for normal AppKit launch, then briefly opens, closes and reopens its window, checking visibility and preservation of the helper's accessory activation policy. It has no device bridge or registered hotkeys. These checks do not replace live keyboard/VoiceOver use, permission granting, restart or signed-update acceptance.

The review candidate adds fail-closed handling for unreadable approval trees, rejects a control labeled as both approval and denial, prevents superseded app launches from activating, and handles a closed bridge pipe without SIGPIPE termination. Fixtures cover these changes, including a real exited child process. The app-activation regression is a source assertion; rapid-launch race conditions were not independently tested live.

Further review requires every nonempty approval label to identify the same permitted action and aborts Copy when a response tree is unreadable, including Claude toolbar retries. Permission-container attribute errors and incomplete workspace child reads also abort selection. These error cases have synthetic coverage. Normal operation on the updated build was physically tested as recorded below.

## Current USB and Bluetooth acceptance

On 2026-09-21, USB testing found that Copy response beeped in Codex inside ChatGPT, including in a short synthetic conversation. Version 0.2.2, build 4, was installed, but a later process check found an older 0.1.0 recovery copy running instead. The helper executing at the time of the reported failure was not independently established. The on-screen Copy button worked, and the tester reported that Claude Copy still worked. Inspector evidence showed the OpenAI Copy button inside a one-child `contents` group, which the direct-button selector skipped. The 0.2.3 candidate supports that wrapper and retains the newest-response and ambiguity checks. Fixtures cover direct and wrapped buttons, code-block exclusion, transient Copied labels and failed Accessibility reads. Physical confirmation of this candidate remains pending; earlier Copy passes do not establish current compatibility.

The signed, notarized 0.2.3 build 5 candidate from `2d0b83470b81d9dd2516ea8138c301c6e1f147e9` passed the isolated full test suite, exact-head review and both CI platforms. Packaging checks verified both Mac architectures, the stapled ticket and Gatekeeper acceptance. The old recovery process was stopped before installing the candidate at the existing application path. Its running path and installed executable SHA-256, `3f602faf645a8acb68ecd0e6033a6a3cc9edd243e1108fb737b32f48ad560963`, were verified. The previous installation remains recoverable. The signing requirement matched the previous installed app; permissions and device configuration were not changed. After the Mac was unlocked, the installed helper's setup window showed Accessibility trusted, Input Monitoring trusted and Device bridge connected. Physical Copy behavior remains unverified.

On 2026-09-16, the tester confirmed the controlled update to version 0.2.1, build 3, from source `5c5098d3f264b3586ecef7ba89ba2d2df72497ed`. The full four-layer cycle passed over USB and Bluetooth with setup open, without removing, re-adding or toggling either Accessibility or Input Monitoring. This is a user-reported switching and permission-retention pass for this update, not a new test of every control or failure mode. A read-only check confirmed the installed version and build number, and its executable SHA-256 matched the signed, notarized candidate: `b271f0a96ceccc7081e7eb1559d9c6acdf8b2ab77b991e50c063db0569ce7728`.

On 2026-09-16, the tester confirmed the full four-layer cycle over USB and Bluetooth with setup open on the signed, notarized build from `7e3fa97c075e376400fbe5eb696a672617dda704`. Its installed bundle matches the verified release, and its executable SHA-256 is `062629abb5b5bd662f58282736dcb2f02572ff53a13475b3262b847ff636a76b`. This is a user-reported switching pass, not a new test of every control or failure mode. The permission entries appeared to remain after replacement, but the tester removed and re-added both, so permission retention is unverified.

Fresh-install testing of the earlier wizard build from `152a7384b2f4c3ff3b214dd064cb8fb29a1677c6` found that Claude did not come forward while setup was open. Layers 3/4 still selected the correct view after Claude was brought forward manually. Closing setup restored app switching. The accessory activation-policy correction has both fixture coverage and the user-reported switching result above.

Version 0.2.1, build 3, contains no runtime or device-profile changes from the preceding signed release. For future signed-update tests, replace the app at the same location, keep both existing permission grants untouched, and test the full four-layer cycle on USB and Bluetooth with setup open. Do not reapply the device profile. If either permission fails, record the failure before changing settings. The successful update above does not establish retention for every future build or system configuration.

On 2026-09-15, the tester reported correct wired and Bluetooth operation on the Developer ID-signed, notarized build from `3d068c4c299c276c3bfb7017dd3d248f78d6210e`. Its executable SHA-256 is `1eecc85b0f43d49fc306edfe7eedec49bc8d2a2cf6a790aac09fcb1ddcbf9f4b`. Both permission entries had to be removed and re-added, then the app relaunched, before it worked. This is a user-reported normal-operation pass, not evidence that a later signed update retains permissions. The new setup wizard requires its own signed-build acceptance; the earlier result does not validate it.

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

| Test | Tested build | 1 Codex | 2 ChatGPT | 3 Claude Code | 4 Claude Chat |
| --- | --- | --- | --- | --- | --- |
| Layer selects correct foreground view, setup open | `5c5098d` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Dictation start/stop and insertion | `ed16b63` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| New chat, Escape, @, Backspace, Undo, Shift+Return (⇧ ↵), Submit | `ed16b63` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Search and model picker | `ed16b63` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Copy response | `ed16b63` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Y allows once, X denies a permission request | `ed16b63` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |
| Y/X with no request leave KEEP THIS DRAFT untouched | Not verified | Pending | Pending | Pending | Pending |
| Joystick all eight directions and dial rotation/press | `ed16b63` | User-reported pass | User-reported pass | User-reported pass | User-reported pass |

Each pass applies only to its row's tested build on both USB and Bluetooth. The full commit IDs and executable hashes are recorded above. The `ed16b63` control results do not establish control coverage on `5c5098d`; only switching and signed-update permission retention were confirmed on version 0.2.1, build 3. Three consecutive dictation attempts with exactly one insertion each, and Copy discrimination between assistant responses, user text and code blocks, still need explicit results.

Test the full 1 → 2 → 3 → 4 → 1 cycle. Confirm both foreground app and selected view at each step, not just device colors. Record switching separately from action-key acceptance; a passing cycle does not verify dictation, Copy or approvals.

Also test foreground routing with a mismatched layer, rapid layer changes, USB disconnect/reconnect, missing Accessibility permission, missing Input Monitoring permission, repeated Claude copy after hidden toolbar reveal, two- and three-button permission panels, unrelated apps, and quitting/relaunching the helper. Quit must terminate its USB child; no standalone listener or action log should remain.

After replacing an ad-hoc-signed build, check recovery from stale permissions: remove and re-add the installed app in both Accessibility and Input Monitoring, enable both, quit and reopen it, then repeat the full switching cycle. Perform permission changes only with the user's authorization. Do not assume that an enabled permission switch means the current build is trusted.

Check the helper menu while connected, after disconnecting the device, and after reconnecting it. A bridge failure must show the warning icon and recovery guidance; a new ready handshake must restore connected status. Missing Accessibility and missing Input Monitoring must each appear by name, independently of bridge status. A failed workspace switch must not be reported as a disconnected device. “Request sent” is not proof that the expected view is visible.

For ChatGPT approval checks, verify the visible Permissions card with and without its optional approval dropdown. Y must select only Allow once and X only Deny. Neither key may open the dropdown, act on similarly named controls outside the card, or act when more than one permission card is present. Unsupported card structures must do nothing.

Check the interactive reference in a browser too: all four layer buttons, paired key highlighting, the eight joystick directions and the mobile layout.
