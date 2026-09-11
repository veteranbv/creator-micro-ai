import CoreGraphics

enum WorkspaceShortcut: String, CaseIterable {
    case chatgpt
    case codex

    var keyCode: CGKeyCode {
        switch self {
        case .chatgpt: return 0x12 // ANSI 1, verified in the installed app.
        case .codex: return 0x14 // ANSI 3, verified in the installed app.
        }
    }

    var label: String { self == .chatgpt ? "Control+1" : "Control+3" }

    // Build the entire sequence before posting anything, so allocation failure
    // cannot leave a partially pressed shortcut in the destination app.
    func makeEvents() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        let control: CGKeyCode = 0x3B
        let sequence: [(CGKeyCode, Bool, CGEventFlags)] = [
            (control, true, .maskControl),
            (keyCode, true, .maskControl),
            (keyCode, false, .maskControl),
            (control, false, [])
        ]
        var events: [CGEvent] = []
        for (key, down, flags) in sequence {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                return nil
            }
            if key == control { event.type = .flagsChanged }
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            events.append(event)
        }
        return events
    }
}
