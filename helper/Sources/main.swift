import AppKit
import ApplicationServices
import Foundation

private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    var raw: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &raw)
    return ControllerTargetPolicy.attributeValue(status: status, value: raw as? String, absent: "")
}

private func workspaceControls(in app: NSRunningApplication) -> (chat: AXUIElement, code: AXUIElement)? {
    guard app.bundleIdentifier == "com.anthropic.claudefordesktop" else { return nil }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let raw = attribute(root, kAXFocusedWindowAttribute),
          CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    let window = unsafeBitCast(raw, to: AXUIElement.self)
    return WorkspaceSelection.controls(root: window, labels: comparableLabels,
        children: {
            var raw: CFTypeRef?
            let status = AXUIElementCopyAttributeValue($0, kAXChildrenAttribute as CFString, &raw)
            return ControllerTargetPolicy.childValues(status: status, values: raw as? [AXUIElement])
        },
        isRadio: { stringAttribute($0, kAXRoleAttribute) == "AXRadioButton" })
}

private func detectMode() -> WorkspaceMode? {
    guard AXIsProcessTrusted(),
          let app = NSWorkspace.shared.frontmostApplication,
          let bundleID = app.bundleIdentifier else {
        return nil
    }

    switch bundleID {
    case "com.openai.codex":
        // The page title does not identify Chat versus Work versus Codex.
        // Keep the user's physical layer instead of guessing and reversing it.
        return nil

    case "com.anthropic.claudefordesktop":
        guard let controls = workspaceControls(in: app),
              let chat = attribute(controls.chat, kAXValueAttribute) as? NSNumber,
              let code = attribute(controls.code, kAXValueAttribute) as? NSNumber,
              chat.boolValue != code.boolValue else { return nil }
        return code.boolValue ? .claudeCode : .claude

    default:
        return nil
    }
}

private func comparableLabels(for element: AXUIElement) -> [String]? {
    var labels: [String] = []
    for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute] {
        guard let text = stringAttribute(element, key) else { return nil }
        labels.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return labels
}

private func pressWorkspaceButton(in app: NSRunningApplication, mode: WorkspaceMode) -> Bool {
    guard [.claude, .claudeCode].contains(mode),
          NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
          let controls = workspaceControls(in: app) else { return false }
    let target = mode == .claudeCode ? controls.code : controls.chat
    guard (attribute(target, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { return false }
    return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
}

private var activationGeneration = 0
private var activationInProgress = false
private var health = HelperHealth()

private func activate(_ mode: WorkspaceMode, completion: @escaping (Bool) -> Void) {
    activationGeneration += 1
    let generation = activationGeneration
    activationInProgress = true
    health.beginSwitch()
    func finish(_ success: Bool) {
        guard generation == activationGeneration else { return }
        activationInProgress = false
        health.finishSwitch(success: success)
        completion(success)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    // A superseded open request must not steal focus before its callback runs.
    configuration.activates = false
    configuration.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: mode.appURL, configuration: configuration) { app, error in
        guard error == nil, let app else {
            DispatchQueue.main.async { finish(false) }
            return
        }
        DispatchQueue.main.async {
            guard generation == activationGeneration else { return }
            app.activate(options: [.activateAllWindows])
            guard AXIsProcessTrusted() else {
                finish(false)
                return
            }
            if let shortcut = WorkspaceShortcut(rawValue: mode.rawValue) {
                func sendWhenReady(_ attempt: Int) {
                    guard generation == activationGeneration else { return }
                    guard !app.isTerminated, app.bundleIdentifier == "com.openai.codex",
                          app.bundleURL?.lastPathComponent == "ChatGPT.app" else {
                        finish(false)
                        return
                    }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                        guard attempt < 20 else {
                            finish(false)
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { sendWhenReady(attempt + 1) }
                        return
                    }
                    guard AXIsProcessTrusted(), let events = shortcut.makeEvents() else {
                        finish(false)
                        return
                    }
                    // The physical layer change requests one shortcut. Do not
                    // retry delivery or inspect page titles to infer success.
                    for event in events { event.postToPid(app.processIdentifier) }
                    finish(true)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sendWhenReady(0) }
                return
            }
            func check(_ attempt: Int) {
                guard generation == activationGeneration else { return }
                if detectMode() == mode {
                    finish(true)
                    return
                }
                guard attempt < 10 else {
                    finish(false)
                    return
                }
                // Some desktop builds expose no numeric radio value. A successful
                // targeted press must not be repeated just because state is unreadable.
                if pressWorkspaceButton(in: app, mode: mode) {
                    finish(true)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check(attempt + 1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { check(0) }
        }
    }
}

// Setup explains each permission before requesting it.
let trusted = AXIsProcessTrusted()
health.accessibilityTrusted = trusted
health.inputMonitoringTrusted = CGPreflightListenEventAccess()

private let bridge = DeviceBridge()
private var lastObserved: WorkspaceMode?
private var lastApplied: WorkspaceMode?
private var pendingLayer: Int?
private var pendingRequest: Int?
private var pendingSince = Date.distantPast
private var baselineReceived = false
private var layerSelection = LayerSelection()
private var focusRetryAfter = Date.distantPast
private var lastPermissionState = trusted

bridge.onFailure = { health.bridgeFailed($0) }
bridge.onMessage = { message in
    health.receive(type: message.type, layer: message.layer)
    switch message.type {
    case "ready":
        guard let readyLayer = message.layer, (1...4).contains(readyLayer) else { return }
        let changedLayer = layerSelection.ready(message.layer)
        baselineReceived = true
        pendingLayer = nil
        pendingRequest = nil
        lastApplied = nil
        if let layer = changedLayer, let mode = WorkspaceMode.from(layer: layer) {
            activate(mode) { success in
                if success {
                    lastObserved = mode
                    lastApplied = mode
                } else {
                    focusRetryAfter = Date().addingTimeInterval(3)
                }
            }
        }

    case "layer":
        guard baselineReceived, let layer = message.layer else { return }
        layerSelection.observe(layer)
        if pendingLayer == layer {
            pendingLayer = nil
            return
        }
        guard let mode = WorkspaceMode.from(layer: layer) else { return }
        pendingLayer = nil
        pendingRequest = nil
        activate(mode) { success in
            if success {
                lastObserved = mode
                lastApplied = mode
            } else {
                lastApplied = nil
                focusRetryAfter = Date().addingTimeInterval(3)
            }
        }

    case "applied":
        layerSelection.observe(message.layer)
        if message.requestId == pendingRequest, message.layer == pendingLayer {
            lastApplied = message.layer.flatMap(WorkspaceMode.from)
            pendingLayer = nil
            pendingRequest = nil
        }

    case "error":
        baselineReceived = false
        if activationInProgress { layerSelection.interruptActivation() }
        activationGeneration += 1
        activationInProgress = false
        pendingLayer = nil
        pendingRequest = nil
        lastApplied = nil
        focusRetryAfter = Date().addingTimeInterval(3)

    default:
        break
    }
}
if health.accessibilityTrusted && health.inputMonitoringTrusted { bridge.start() }

Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
    let permission = AXIsProcessTrusted()
    health.accessibilityTrusted = permission
    health.inputMonitoringTrusted = CGPreflightListenEventAccess()
    if permission && health.inputMonitoringTrusted { bridge.start() }
    health.checkStartup(now: ProcessInfo.processInfo.systemUptime)
    lifecycle.updateStatus()
    if permission != lastPermissionState {
        lastPermissionState = permission
        lastObserved = nil
        lastApplied = nil
    }
    guard permission, baselineReceived, !activationInProgress else { return }
    if pendingLayer != nil, Date().timeIntervalSince(pendingSince) > 12 {
        pendingLayer = nil
        pendingRequest = nil
        lastApplied = nil
    }
    guard let mode = detectMode() else { return }
    if mode != lastObserved {
        lastObserved = mode
    }
    guard mode != lastApplied, pendingLayer == nil, Date() >= focusRetryAfter else { return }
    pendingLayer = mode.layer
    if let request = bridge.focus(mode) {
        pendingRequest = request
        pendingSince = Date()
    } else {
        pendingLayer = nil
    }
}

// AppKit must dispatch registered Carbon hotkeys; a Foundation timer loop does not.
private let application = NSApplication.shared
application.setActivationPolicy(.accessory)
private let controllerActions = ControllerActions()
controllerActions.onClaudeCopyFailure = { health.claudeCopyFailure = $0 }
controllerActions.start()
private let lifecycle = HelperLifecycle(bridge: bridge, health: { health })
application.delegate = lifecycle
lifecycle.configureMenu()
application.run()
