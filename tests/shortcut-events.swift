import CoreGraphics

@main
enum ShortcutEventTests {
    static func main() {
        for (mode, key): (WorkspaceShortcut, Int64) in [(.chatgpt, 0x12), (.codex, 0x14)] {
            guard let events = mode.makeEvents() else { fatalError("Could not construct shortcut") }
            precondition(events.count == 4)
            precondition(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0x3B, key, key, 0x3B])
            precondition(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
            precondition(events.map { $0.flags.rawValue } == [262144, 262144, 262144, 0])
            precondition(events.allSatisfy { $0.getIntegerValueField(.keyboardEventAutorepeat) == 0 })
        }
        precondition(WorkspaceShortcut(rawValue: "claude") == nil)
        precondition(WorkspaceShortcut(rawValue: "claude-code") == nil)
        print("PASS: exact Chat/Codex mappings, balanced keys, released Control, no repeat, no Claude changes. No events were posted.")
    }
}
