import AppKit
import ApplicationServices
import Foundation

enum WorkspaceMode: String, CaseIterable {
    case codex
    case chatgpt
    case claudeCode = "claude-code"
    case claude

    var processToken: String {
        switch self {
        case .codex: return "cc.worklouder.ai.codex"
        case .claudeCode: return "cc.worklouder.ai.claude-code"
        case .claude: return "cc.worklouder.ai.claude"
        case .chatgpt: return "cc.worklouder.ai.chatgpt"
        }
    }

    var layer: Int {
        switch self {
        case .codex: return 1
        case .chatgpt: return 2
        case .claudeCode: return 3
        case .claude: return 4
        }
    }

    var appURL: URL {
        switch self {
        case .codex, .chatgpt: return URL(fileURLWithPath: "/Applications/ChatGPT.app")
        case .claudeCode, .claude: return URL(fileURLWithPath: "/Applications/Claude.app")
        }
    }

    var workspaceButtonLabels: [String] {
        switch self {
        case .codex: return ["Codex"]
        case .chatgpt: return ["ChatGPT", "Home"]
        case .claudeCode: return ["Code"]
        case .claude: return ["Chat and Cowork", "Chat", "Home"]
        }
    }

    static func from(layer: Int) -> WorkspaceMode? {
        allCases.first(where: { $0.layer == layer })
    }
}

struct BridgeMessage: Decodable {
    let type: String
    let layer: Int?
    let requestId: Int?
}

private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    if let value = attribute(element, name) as? String {
        return value
    }
    if let value = attribute(element, name) as? URL {
        return value.absoluteString
    }
    return nil
}

private func elements(for app: NSRunningApplication, limit: Int = 2_000) -> [AXUIElement] {
    var queue: [AXUIElement] = [AXUIElementCreateApplication(app.processIdentifier)]
    var cursor = 0
    while cursor < queue.count, cursor < limit {
        let element = queue[cursor]
        cursor += 1
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            queue.append(contentsOf: children.prefix(max(0, limit - queue.count)))
        }
    }
    return Array(queue.prefix(limit))
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
        // Current Claude exposes mode selection as radio buttons.
        for element in elements(for: app) {
            guard stringAttribute(element, kAXRoleAttribute) == "AXRadioButton",
                  (attribute(element, kAXValueAttribute) as? NSNumber)?.boolValue == true else { continue }
            let labels = comparableLabels(for: element)
            if labels.contains("Code") { return .claudeCode }
            if labels.contains("Chat and Cowork") || labels.contains("Chat") { return .claude }
        }
        return nil

    default:
        return nil
    }
}

private func comparableLabels(for element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
        .compactMap { stringAttribute(element, $0) }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func pressWorkspaceButton(in app: NSRunningApplication, labels: [String]) -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
    let wanted = labels.map { $0.lowercased() }
    for element in elements(for: app) {
        guard ["AXButton", "AXRadioButton", "AXTab"].contains(stringAttribute(element, kAXRoleAttribute) ?? "") else { continue }
        let actual = comparableLabels(for: element).map { $0.lowercased() }
        if wanted.contains(where: { candidate in actual.contains(candidate) }) {
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }
    }
    return false
}

private var activationGeneration = 0
private var activationInProgress = false

private func activate(_ mode: WorkspaceMode, completion: @escaping (Bool) -> Void) {
    activationGeneration += 1
    let generation = activationGeneration
    activationInProgress = true
    func finish(_ success: Bool) {
        guard generation == activationGeneration else { return }
        activationInProgress = false
        completion(success)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: mode.appURL, configuration: configuration) { app, error in
        if error != nil {
            finish(false)
            return
        }
        guard let app else {
            finish(false)
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
                _ = pressWorkspaceButton(in: app, labels: mode.workspaceButtonLabels)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check(attempt + 1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { check(0) }
        }
    }
}

let promptOptions = [
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(promptOptions)

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

bridge.onMessage = { message in
    switch message.type {
    case "ready":
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
        pendingLayer = nil
        pendingRequest = nil
        lastApplied = nil
        focusRetryAfter = Date().addingTimeInterval(3)

    default:
        break
    }
}
bridge.start()

Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
    let permission = AXIsProcessTrusted()
    if permission != lastPermissionState {
        lastPermissionState = permission
        lastObserved = nil
        lastApplied = nil
    }
    guard permission, !activationInProgress else { return }
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
controllerActions.start()
private let lifecycle = HelperLifecycle(bridge: bridge)
application.delegate = lifecycle
lifecycle.configureMenu()
application.run()
