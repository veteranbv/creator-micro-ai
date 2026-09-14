final class Node {
    let labels: [String]
    let radio: Bool
    var children: [Node]
    init(_ label: String = "", radio: Bool = false, _ children: [Node] = []) {
        self.labels = [label]
        self.radio = radio
        self.children = children
    }
}

@main enum WorkspaceSelectionTests {
    static func main() {
        let chat = Node("Chat and Cowork", radio: true)
        let code = Node("Code", radio: true)
        let mode = Node("Mode", [chat, code])
        let sidebar = Node("Sidebar", [mode])
        let pane = Node("Primary pane", [Node("Code", radio: true), Node("Chat", radio: true)])
        let root = Node("", [sidebar, pane])
        var paneReads = 0
        func select(_ node: Node) -> (chat: Node, code: Node)? {
            WorkspaceSelection.controls(root: node, labels: { $0.labels }, children: {
                if $0 === pane { paneReads += 1 }
                return $0.children
            }, isRadio: { $0.radio })
        }
        precondition(select(root)?.chat === chat)
        precondition(select(root)?.code === code)
        precondition(paneReads == 0)
        precondition(select(pane) == nil)
        precondition(select(Node("", [sidebar, sidebar])) == nil)
        sidebar.children = [mode, mode]
        precondition(select(root) == nil)
        sidebar.children = [mode]
        mode.children = [chat]
        precondition(select(root) == nil)
        mode.children = [chat, Node("Code")]
        precondition(select(root) == nil)
        mode.children = [chat, code, Node("Extra", radio: true)]
        precondition(select(root) == nil)
        precondition(select(Node("", Array(repeating: Node(), count: 101))) == nil)
        mode.children = [chat, code]
        func wrapped(_ node: Node, levels: Int) -> Node {
            (0..<levels).reduce(node) { result, _ in Node("", [result]) }
        }
        // The native window exposes wrappers that a summarized UI tree omits.
        let nativeWindow = wrapped(root, levels: 12)
        precondition(select(nativeWindow)?.chat === chat)
        precondition(select(nativeWindow)?.code === code)
        precondition(paneReads == 0)
        precondition(select(wrapped(sidebar, levels: 32))?.code === code)
        precondition(select(wrapped(sidebar, levels: 33)) == nil)
        precondition(select(Node("", [sidebar, wrapped(sidebar, levels: 12)])) == nil)
        for unreadable in [root, sidebar, mode] {
            precondition(WorkspaceSelection.controls(root: root, labels: { $0.labels },
                children: { $0 === unreadable ? nil : $0.children }, isRadio: { $0.radio }) == nil)
        }
        let hiddenBranch = Node("", [sidebar])
        let incompleteWindow = Node("", [sidebar, hiddenBranch])
        precondition(WorkspaceSelection.controls(root: incompleteWindow, labels: { $0.labels },
            children: { $0 === hiddenBranch ? nil : $0.children }, isRadio: { $0.radio }) == nil)
        precondition(select(wrapped(Node("", Array(repeating: Node(), count: 101)), levels: 12)) == nil)
        print("PASS: sidebar Mode pair, nested native windows, composer pruning, ambiguity, incomplete controls and traversal budgets. No app access.")
    }
}
