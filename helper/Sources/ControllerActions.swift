import AppKit
import ApplicationServices
import Carbon

// Selection rules accept plain test trees as well as live accessibility elements.
enum ControllerTargetPolicy {
    static func isOpenAIResponseGroup(_ classes: [String]) -> Bool {
        Set(["relative", "shrink-0"]).isSubset(of: Set(classes))
    }

    static func directResponseCopy<Node>(children: [Node], isAssistantHeading: (Node) -> Bool,
        isUserHeading: (Node) -> Bool, isCopy: (Node) -> Bool) -> Node? {
        guard let heading = children.lastIndex(where: isAssistantHeading) else { return nil }
        // Accessibility can flatten a turn's heading, body groups, and buttons into siblings.
        let response = children.dropFirst(heading + 1).prefix { !isUserHeading($0) }
        let copies = response.filter(isCopy)
        return copies.count == 1 ? copies[0] : nil
    }

    static func isClaudeMessageName(_ name: String) -> Bool {
        let parts = name.split(separator: " ")
        guard [2, 4].contains(parts.count), parts[0] == "Message",
              let index = Int(parts[1]), index > 0 else { return false }
        if parts.count == 2 { return true }
        return parts[2] == "of" && (Int(parts[3]) ?? 0) >= index
    }

    static func isClaudeActionReveal(_ name: String) -> Bool {
        name == "Show message actions" || name.hasPrefix("Show message actions for Claude responded:")
    }

    static func pairedApproval<Node>(approvals: [Node], declines: [Node], approve: Bool,
        parent: (Node) -> Node?, group: (Node, Int) -> [Node], equal: (Node, Node) -> Bool) -> Node? {
        guard approvals.count == 1, declines.count == 1 else { return nil }
        var ancestor = approvals[0]
        for _ in 0..<4 {
            guard let next = parent(ancestor) else { break }
            ancestor = next
            let contents = group(ancestor, 101)
            if contents.count <= 100, contents.contains(where: { equal($0, declines[0]) }) {
                return approve ? approvals[0] : declines[0]
            }
        }
        return nil
    }

    static func isClaudeApprovalName(_ name: String, approve: Bool) -> Bool {
        // Claude renumbers Allow once when Always allow is absent from the panel.
        let names = approve ? ["Allow once", "Allow once 2", "Allow once 3"] : ["Deny", "Deny 1"]
        return names.contains(name)
    }

    static func claudePermissionContents<Node>(requests: [Node], group: (Node, Int) -> [Node]) -> [Node] {
        guard requests.count == 1 else { return [] }
        let contents = group(requests[0], 101)
        return contents.count < 101 ? contents : []
    }

    static func isOpenAIApprovalForm(_ classes: [String]) -> Bool {
        Set(["@max-md/approval-card:flex-col", "@max-md/approval-card:items-stretch"])
            .isSubset(of: Set(classes))
    }

    static func openAIPermissionButtons<Node>(nodes: [Node], children: (Node) -> [Node]?,
        isGroup: (Node) -> Bool, isAlert: (Node) -> Bool, isPermissionsText: (Node) -> Bool,
        isForm: (Node) -> Bool, isButton: (Node) -> Bool) -> [Node] {
        // The permission alert and action form are siblings, not nested inside each other.
        let alerts = nodes.filter { node in
            isAlert(node) && (children(node)?.contains(where: isPermissionsText) == true)
        }
        guard alerts.count == 1 else { return [] }
        let cards = nodes.filter { node in
            guard isGroup(node), let parts = children(node), parts.count == 2 else { return false }
            return parts.filter { part in
                isAlert(part) && (children(part)?.contains(where: isPermissionsText) == true)
            }.count == 1
        }
        guard cards.count == 1, let parts = children(cards[0]) else { return [] }
        let forms = parts.filter(isForm)
        guard forms.count == 1, let buttons = children(forms[0]),
              (2...3).contains(buttons.count), buttons.allSatisfy(isButton) else { return [] }
        return buttons
    }
}

// Reserved controller shortcuts only. No event tap, typed-text capture, or clipboard reads.
final class ControllerActions {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let signature: UInt32 = 0x574C4149
    private var copyPending = false


    func start() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let owner = Unmanaged<ControllerActions>.fromOpaque(context).takeUnretainedValue()
            guard id.signature == owner.signature else { return OSStatus(eventNotHandledErr) }
            owner.receive(id.id)
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type,
                                        Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { NSSound.beep(); return }
        let keys = [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17]
        for (index, key) in keys.enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: signature, id: UInt32(index + 1)), GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive), &ref)
            if result == noErr, let ref { refs.append(ref) }
            else { NSSound.beep() }
        }
    }

    private func receive(_ id: UInt32) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              ["com.openai.codex", "com.anthropic.claudefordesktop"].contains(app.bundleIdentifier ?? "") else { return }
        // Firmware releases the remaining modifiers after the function key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  AXIsProcessTrusted() else { return }
            self.perform(id, app: app)
        }
    }

    private func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func labels(_ e: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { value(e, $0) as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private func matches(_ e: AXUIElement, _ names: Set<String>) -> Bool { labels(e).contains { names.contains($0) } }
    private func descendants(_ root: AXUIElement, limit: Int = 5000) -> [AXUIElement] {
        var result: [AXUIElement] = [], stack = [root]
        while let e = stack.popLast(), result.count < limit {
            result.append(e)
            stack.append(contentsOf: ((value(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).reversed())
        }
        return result
    }
    private func actionable(_ e: AXUIElement) -> Bool {
        let role = value(e, kAXRoleAttribute) as? String
        return [kAXButtonRole, kAXPopUpButtonRole].contains(role ?? "") && (value(e, kAXEnabledAttribute) as? Bool) != false
    }
    private func press(_ e: AXUIElement, app: NSRunningApplication) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
        return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
    }
    private func parent(_ e: AXUIElement) -> AXUIElement? {
        guard let raw = value(e, kAXParentAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    private func focusedWindow(_ app: NSRunningApplication) -> AXUIElement? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let raw = value(root, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    private func latestClaudeMessage(_ window: AXUIElement) -> AXUIElement? {
        descendants(window).reversed().first { element in
            labels(element).contains(where: ControllerTargetPolicy.isClaudeMessageName)
                && descendants(element, limit: 1000).contains { labels($0).contains { $0.hasPrefix("Claude responded:") } }
        }
    }
    private func claudeCopyControl(_ message: AXUIElement) -> AXUIElement? {
        let toolbars = descendants(message, limit: 1000).filter {
            (value($0, kAXRoleAttribute) as? String) == kAXToolbarRole && matches($0, ["Message actions"])
        }
        guard toolbars.count == 1 else { return nil }
        let copies = descendants(toolbars[0], limit: 100).filter { actionable($0) && matches($0, ["Copy"]) }
        return copies.count == 1 ? copies[0] : nil
    }
    private func finishCopy(_ success: Bool) {
        copyPending = false
        if !success { NSSound.beep() }
    }
    private func waitForClaudeCopy(app: NSRunningApplication, window: AXUIElement, message: AXUIElement, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let currentWindow = self.focusedWindow(app), CFEqual(currentWindow, window),
                  let currentMessage = self.latestClaudeMessage(currentWindow), CFEqual(currentMessage, message) else {
                self.finishCopy(false)
                return
            }
            if let target = self.claudeCopyControl(currentMessage) {
                self.finishCopy(self.press(target, app: app))
            } else if attempts > 1 {
                self.waitForClaudeCopy(app: app, window: window, message: message, attempts: attempts - 1)
            } else { self.finishCopy(false) }
        }
    }
    private func perform(_ id: UInt32, app: NSRunningApplication) {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawWindow = value(root, kAXFocusedWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return }
        let window = unsafeBitCast(rawWindow, to: AXUIElement.self)
        let all = descendants(window)
        guard all.count < 5000 else { NSSound.beep(); return }
        let controls = all.filter(actionable)
        let claude = app.bundleIdentifier == "com.anthropic.claudefordesktop"
        var target: AXUIElement?
        switch id {
        case 1:
            if !claude {
                // The app-scoped model-picker shortcut.
                let source = CGEventSource(stateID: .privateState)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_M), keyDown: down)
                    event?.flags = [.maskControl, .maskShift]
                    event?.postToPid(app.processIdentifier)
                }
                return
            }
            let candidates = controls.filter { labels($0).contains { $0.hasPrefix("Model: ") } }
            if candidates.count == 1 { target = candidates[0] }
        case 2:
            guard !copyPending else { return }
            // A truncated window tree cannot establish which response is last.
            guard all.count < 5000 else { finishCopy(false); return }
            if !claude {
                // Installed app: tooltip is Copy response, but aria-label is Copy.
                // Include Copied when selecting the latest row so a second tap cannot copy an older response.
                let isCopy: (AXUIElement) -> Bool = { self.actionable($0) && self.matches($0, ["Copy", "Copied", "Copy response"]) }
                // Copy's parent can be a flattened turn group.
                let children: (AXUIElement) -> [AXUIElement] = {
                    self.value($0, kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
                let assistantHeading: (AXUIElement) -> Bool = {
                    (self.value($0, kAXRoleAttribute) as? String) == "AXHeading"
                        && self.labels($0).contains { $0 == "ChatGPT said:" || $0.hasPrefix("ChatGPT said: ") }
                }
                let userHeading: (AXUIElement) -> Bool = {
                    (self.value($0, kAXRoleAttribute) as? String) == "AXHeading"
                        && self.labels($0).contains { $0 == "You said:" || $0.hasPrefix("You said: ") }
                }
                let groups = all.filter {
                    (value($0, kAXRoleAttribute) as? String) == kAXGroupRole
                        && ControllerTargetPolicy.isOpenAIResponseGroup(value($0, "AXDOMClassList") as? [String] ?? [])
                        && children($0).contains(where: assistantHeading)
                }
                if let latest = groups.last {
                    target = ControllerTargetPolicy.directResponseCopy(children: children(latest),
                        isAssistantHeading: assistantHeading, isUserHeading: userHeading, isCopy: isCopy)
                }
                if let candidate = target, matches(candidate, ["Copied"]) { target = nil }
            } else {
                if let message = latestClaudeMessage(window) {
                    target = claudeCopyControl(message)
                    if target == nil {
                        let reveal = descendants(message, limit: 1000).filter {
                            actionable($0) && labels($0).contains(where: ControllerTargetPolicy.isClaudeActionReveal)
                        }
                        if reveal.count == 1, press(reveal[0], app: app) {
                            copyPending = true
                            waitForClaudeCopy(app: app, window: window, message: message, attempts: 6)
                            return
                        }
                    }
                }
            }
        case 3, 4:
            let approvals: [AXUIElement]
            let declines: [AXUIElement]
            if claude {
                // Observed Claude panel: Permission request: run, with numbered action labels.
                let requests = all.count < 5000 ? all.filter {
                    (value($0, kAXRoleAttribute) as? String) == kAXGroupRole
                        && labels($0).contains { $0.hasPrefix("Permission request: ") }
                } : []
                let requestControls = ControllerTargetPolicy.claudePermissionContents(requests: requests,
                    group: { self.descendants($0, limit: $1) }).filter(actionable)
                approvals = requestControls.filter { labels($0).contains {
                    ControllerTargetPolicy.isClaudeApprovalName($0, approve: true)
                } }
                declines = requestControls.filter { labels($0).contains {
                    ControllerTargetPolicy.isClaudeApprovalName($0, approve: false)
                } }
            } else {
                let requestControls = ControllerTargetPolicy.openAIPermissionButtons(nodes: all,
                    children: { self.value($0, kAXChildrenAttribute) as? [AXUIElement] },
                    isGroup: { (self.value($0, kAXRoleAttribute) as? String) == kAXGroupRole },
                    isAlert: {
                        (self.value($0, kAXRoleAttribute) as? String) == kAXGroupRole
                            && (self.value($0, kAXSubroleAttribute) as? String) == "AXApplicationAlert"
                    },
                    isPermissionsText: {
                        (self.value($0, kAXRoleAttribute) as? String) == kAXStaticTextRole
                            && (self.matches($0, ["Permissions"])
                                || (self.value($0, kAXValueAttribute) as? String) == "Permissions")
                    },
                    isForm: {
                        (self.value($0, kAXRoleAttribute) as? String) == kAXGroupRole
                            && ControllerTargetPolicy.isOpenAIApprovalForm(
                                self.value($0, "AXDOMClassList") as? [String] ?? [])
                    }, isButton: actionable)
                approvals = requestControls.filter { matches($0, ["Allow once"]) }
                declines = requestControls.filter { matches($0, ["Deny"]) }
            }
            target = ControllerTargetPolicy.pairedApproval(approvals: approvals, declines: declines, approve: id == 3,
                parent: parent, group: { self.descendants($0, limit: $1) }, equal: { CFEqual($0, $1) })
        case 5:
            // Both apps label the sidebar control Search, not the settings command name.
            let candidates = controls.filter { matches($0, ["Search"]) }
            if candidates.count == 1 { target = candidates[0] }
        default: return
        }
        if let target, press(target, app: app) { return }
        NSSound.beep()
    }
}
