import AppKit
import ApplicationServices
import Carbon

// Selection rules accept plain test trees as well as live accessibility elements.
enum ControllerTargetPolicy {
    static func attributeValue<Value>(status: AXError, value: Value?, absent: Value) -> Value? {
        switch status {
        case .success: return value
        case .attributeUnsupported, .noValue: return absent
        default: return nil
        }
    }

    static func childValues<Node>(status: AXError, values: [Node]?) -> [Node]? {
        switch status {
        case .success: return values
        case .attributeUnsupported, .noValue: return []
        default: return nil
        }
    }

    static func completeDescendants<Node>(_ root: Node, limit: Int,
        children: (Node) -> [Node]?) -> [Node]? {
        var result: [Node] = [], stack = [root]
        while let node = stack.popLast() {
            guard result.count < limit, let next = children(node) else { return nil }
            result.append(node)
            guard result.count + stack.count + next.count < limit else { return nil }
            stack.append(contentsOf: next.reversed())
        }
        return result
    }

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
        parent: (Node) -> Node?, group: (Node, Int) -> [Node]?, equal: (Node, Node) -> Bool) -> Node? {
        guard approvals.count == 1, declines.count == 1,
              !equal(approvals[0], declines[0]) else { return nil }
        var ancestor = approvals[0]
        for _ in 0..<4 {
            guard let next = parent(ancestor) else { break }
            ancestor = next
            guard let contents = group(ancestor, 101) else { return nil }
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

    static func isApprovalLabels(_ labels: [String], claude: Bool, approve: Bool) -> Bool {
        let names = labels.filter { !$0.isEmpty }
        return !names.isEmpty && names.allSatisfy {
            claude ? isClaudeApprovalName($0, approve: approve) : $0 == (approve ? "Allow once" : "Deny")
        }
    }

    static func claudePermissionContents<Node>(requests: [Node], group: (Node, Int) -> [Node]?) -> [Node] {
        guard requests.count == 1, let contents = group(requests[0], 101) else { return [] }
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

// One selection attempt owns this state. A later successful read cannot erase a failure.
final class ControllerAccessibility {
    private(set) var complete = true
    private let copyAttribute: (AXUIElement, String) -> (AXError, CFTypeRef?)

    init(copyAttribute: @escaping (AXUIElement, String) -> (AXError, CFTypeRef?) = { element, key in
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &raw)
        return (status, raw)
    }) {
        self.copyAttribute = copyAttribute
    }

    func read<Value>(_ element: AXUIElement, _ key: String, absent: Value) -> Value {
        let (status, raw) = copyAttribute(element, key)
        guard let result = ControllerTargetPolicy.attributeValue(status: status, value: raw as? Value, absent: absent) else {
            complete = false
            return absent
        }
        return result
    }

    func labels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].map {
            read(element, $0, absent: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    func matches(_ element: AXUIElement, _ names: Set<String>) -> Bool {
        labels(element).contains { names.contains($0) }
    }
    func role(_ element: AXUIElement) -> String { read(element, kAXRoleAttribute, absent: "") }
    func actionable(_ element: AXUIElement) -> Bool {
        [kAXButtonRole, kAXPopUpButtonRole].contains(role(element)) && read(element, kAXEnabledAttribute, absent: false)
    }
    func children(_ element: AXUIElement) -> [AXUIElement]? {
        let (status, raw) = copyAttribute(element, kAXChildrenAttribute)
        guard let result = ControllerTargetPolicy.childValues(status: status, values: raw as? [AXUIElement]) else {
            complete = false
            return nil
        }
        return result
    }
    func descendants(_ root: AXUIElement, limit: Int = 5000) -> [AXUIElement]? {
        guard let result = ControllerTargetPolicy.completeDescendants(root, limit: limit, children: children) else {
            complete = false
            return nil
        }
        return result
    }
    func uniqueControl(in nodes: [AXUIElement], matching name: (String) -> Bool) -> AXUIElement? {
        let candidates = nodes.filter { actionable($0) && labels($0).contains(where: name) }
        return complete && candidates.count == 1 ? candidates[0] : nil
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
        guard AXIsProcessTrusted(), let window = focusedWindow(app) else { return }
        let approval = id == 3 || id == 4
        let originalTarget = approval ? approvalTarget(id, window: window, claude: app.bundleIdentifier == "com.anthropic.claudefordesktop") : nil
        if approval && originalTarget == nil { NSSound.beep(); return }
        // Firmware releases the remaining modifiers after the function key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  AXIsProcessTrusted() else { return }
            guard let currentWindow = self.focusedWindow(app), CFEqual(currentWindow, window) else { return }
            if approval {
                guard let originalTarget,
                      let currentTarget = self.approvalTarget(id, window: window, claude: app.bundleIdentifier == "com.anthropic.claudefordesktop"),
                      CFEqual(originalTarget, currentTarget) else { NSSound.beep(); return }
                if !self.press(currentTarget, app: app, window: window) { NSSound.beep() }
            } else {
                self.perform(id, app: app, window: window)
            }
        }
    }

    private func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func press(_ e: AXUIElement, app: NSRunningApplication, window: AXUIElement) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let currentWindow = focusedWindow(app), CFEqual(currentWindow, window) else { return false }
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
    func latestClaudeMessage(_ window: AXUIElement, using reads: ControllerAccessibility) -> AXUIElement? {
        guard let nodes = reads.descendants(window) else { return nil }
        for element in nodes.reversed() where reads.labels(element).contains(where: ControllerTargetPolicy.isClaudeMessageName) {
            guard reads.complete, let contents = reads.descendants(element, limit: 1000) else { return nil }
            let response = contents.contains(where: { reads.labels($0).contains { $0.hasPrefix("Claude responded:") } })
            guard reads.complete else { return nil }
            if response { return element }
        }
        return nil
    }
    private func claudeCopyControl(_ message: AXUIElement, using reads: ControllerAccessibility) -> AXUIElement? {
        guard let contents = reads.descendants(message, limit: 1000) else { return nil }
        let toolbars = contents.filter {
            reads.role($0) == kAXToolbarRole && reads.matches($0, ["Message actions"])
        }
        guard toolbars.count == 1, let buttons = reads.descendants(toolbars[0], limit: 100) else { return nil }
        let copies = buttons.filter { reads.actionable($0) && reads.matches($0, ["Copy"]) }
        return reads.complete && copies.count == 1 ? copies[0] : nil
    }
    private func finishCopy(_ success: Bool) {
        copyPending = false
        if !success { NSSound.beep() }
    }
    private func waitForClaudeCopy(app: NSRunningApplication, window: AXUIElement, message: AXUIElement, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let reads = ControllerAccessibility()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let currentWindow = self.focusedWindow(app), CFEqual(currentWindow, window),
                  let currentMessage = self.latestClaudeMessage(currentWindow, using: reads), CFEqual(currentMessage, message) else {
                self.finishCopy(false)
                return
            }
            if let target = self.claudeCopyControl(currentMessage, using: reads) {
                self.finishCopy(self.press(target, app: app, window: window))
            } else if reads.complete && attempts > 1 {
                self.waitForClaudeCopy(app: app, window: window, message: message, attempts: attempts - 1)
            } else { self.finishCopy(false) }
        }
    }
    private func perform(_ id: UInt32, app: NSRunningApplication, window: AXUIElement) {
        let reads = ControllerAccessibility()
        // Every uniqueness-based selector requires a complete tree.
        guard let all = reads.descendants(window) else {
            NSSound.beep()
            return
        }
        guard all.count < 5000 else { NSSound.beep(); return }
        let claude = app.bundleIdentifier == "com.anthropic.claudefordesktop"
        var target: AXUIElement?
        switch id {
        case 1:
            if !claude {
                // The app-scoped model-picker shortcut.
                guard reads.complete, let currentWindow = focusedWindow(app), CFEqual(currentWindow, window),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                let source = CGEventSource(stateID: .privateState)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_M), keyDown: down)
                    event?.flags = [.maskControl, .maskShift]
                    event?.postToPid(app.processIdentifier)
                }
                return
            }
            target = reads.uniqueControl(in: all, matching: { $0.hasPrefix("Model: ") })
        case 2:
            guard !copyPending else { return }
            // A truncated window tree cannot establish which response is last.
            guard all.count < 5000 else { finishCopy(false); return }
            if !claude {
                // Installed app: tooltip is Copy response, but aria-label is Copy.
                // Include Copied when selecting the latest row so a second tap cannot copy an older response.
                let isCopy: (AXUIElement) -> Bool = { reads.actionable($0) && reads.matches($0, ["Copy", "Copied", "Copy response"]) }
                // Copy's parent can be a flattened turn group.
                let assistantHeading: (AXUIElement) -> Bool = {
                    reads.role($0) == "AXHeading"
                        && reads.labels($0).contains { $0 == "ChatGPT said:" || $0.hasPrefix("ChatGPT said: ") }
                }
                let userHeading: (AXUIElement) -> Bool = {
                    reads.role($0) == "AXHeading"
                        && reads.labels($0).contains { $0 == "You said:" || $0.hasPrefix("You said: ") }
                }
                var latestChildren: [AXUIElement]?
                for node in all where reads.role(node) == kAXGroupRole
                    && ControllerTargetPolicy.isOpenAIResponseGroup(reads.read(node, "AXDOMClassList", absent: [String]())) {
                    guard let contents = reads.children(node) else { finishCopy(false); return }
                    if contents.contains(where: assistantHeading) { latestChildren = contents }
                }
                if let latestChildren {
                    target = ControllerTargetPolicy.directResponseCopy(children: latestChildren,
                        isAssistantHeading: assistantHeading, isUserHeading: userHeading, isCopy: isCopy)
                }
                if let candidate = target, reads.matches(candidate, ["Copied"]) { target = nil }
            } else {
                if let message = latestClaudeMessage(window, using: reads) {
                    target = claudeCopyControl(message, using: reads)
                    if target == nil {
                        guard reads.complete, let contents = reads.descendants(message, limit: 1000) else { finishCopy(false); return }
                        let reveal = contents.filter {
                            reads.actionable($0) && reads.labels($0).contains(where: ControllerTargetPolicy.isClaudeActionReveal)
                        }
                        if reads.complete, reveal.count == 1, press(reveal[0], app: app, window: window) {
                            copyPending = true
                            waitForClaudeCopy(app: app, window: window, message: message, attempts: 6)
                            return
                        }
                    }
                }
            }
        case 5:
            // Both apps label the sidebar control Search, not the settings command name.
            target = reads.uniqueControl(in: all, matching: { $0 == "Search" })
        default: return
        }
        if reads.complete, let target, press(target, app: app, window: window) { return }
        NSSound.beep()
    }

    private func approvalTarget(_ id: UInt32, window: AXUIElement, claude: Bool) -> AXUIElement? {
        let reads = ControllerAccessibility()
        guard let all = reads.descendants(window) else { return nil }
        let requestControls: [AXUIElement]
        if claude {
            let requests = all.filter {
                reads.role($0) == kAXGroupRole
                    && reads.labels($0).contains { $0.hasPrefix("Permission request: ") }
            }
            requestControls = ControllerTargetPolicy.claudePermissionContents(requests: requests,
                group: { reads.descendants($0, limit: $1) }).filter(reads.actionable)
        } else {
            requestControls = ControllerTargetPolicy.openAIPermissionButtons(nodes: all,
                children: reads.children,
                isGroup: { reads.role($0) == kAXGroupRole },
                isAlert: {
                    reads.role($0) == kAXGroupRole
                        && reads.read($0, kAXSubroleAttribute, absent: "") == "AXApplicationAlert"
                },
                isPermissionsText: {
                    reads.role($0) == kAXStaticTextRole
                        && (reads.labels($0).contains("Permissions")
                            || reads.read($0, kAXValueAttribute, absent: "") == "Permissions")
                },
                isForm: {
                    reads.role($0) == kAXGroupRole
                        && ControllerTargetPolicy.isOpenAIApprovalForm(reads.read($0, "AXDOMClassList", absent: [String]()))
                }, isButton: reads.actionable)
        }
        var approvals: [AXUIElement] = [], declines: [AXUIElement] = []
        for control in requestControls {
            let names = reads.labels(control)
            if ControllerTargetPolicy.isApprovalLabels(names, claude: claude, approve: true) { approvals.append(control) }
            if ControllerTargetPolicy.isApprovalLabels(names, claude: claude, approve: false) { declines.append(control) }
        }
        guard reads.complete else { return nil }
        let target = ControllerTargetPolicy.pairedApproval(approvals: approvals, declines: declines, approve: id == 3,
            parent: parent, group: { reads.descendants($0, limit: $1) }, equal: { CFEqual($0, $1) })
        return reads.complete ? target : nil
    }
}
