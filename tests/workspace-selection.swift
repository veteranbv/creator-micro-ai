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
        print("PASS: sidebar Mode pair, composer pruning, ambiguity, incomplete controls and traversal budget. No app access.")
    }
}
