// Only the sidebar's Mode group identifies Claude's desktop workspace.
enum WorkspaceSelection {
    static func controls<Node>(root: Node, labels: (Node) -> [String]?,
        children: (Node) -> [Node]?, isRadio: (Node) -> Bool) -> (chat: Node, code: Node)? {
        var queue: [(Node, Int)] = [(root, 0)]
        var cursor = 0
        var sidebars: [Node] = []
        while cursor < queue.count {
            guard cursor < 100 else { return nil }
            let (node, depth) = queue[cursor]
            cursor += 1
            guard let names = labels(node) else { return nil }
            if names.contains("Sidebar") {
                sidebars.append(node)
                continue
            }
            // Do not inspect the conversation or composer when finding navigation.
            if names.contains("Primary pane") { continue }
            guard let next = children(node) else { return nil }
            // Native accessibility wrappers can put the sidebar beyond ten levels.
            // Keep the total node budget and pane pruning independent of that depth.
            guard next.isEmpty || depth < 32, queue.count + next.count <= 100 else { return nil }
            queue.append(contentsOf: next.map { ($0, depth + 1) })
        }
        guard sidebars.count == 1 else { return nil }
        guard let sidebarChildren = children(sidebars[0]), sidebarChildren.count <= 100 else { return nil }
        var groups: [Node] = []
        for child in sidebarChildren {
            guard let names = labels(child) else { return nil }
            if names.contains("Mode") { groups.append(child) }
        }
        guard groups.count == 1 else { return nil }
        guard let radios = children(groups[0]), radios.count == 2, radios.allSatisfy(isRadio) else { return nil }
        var chat: [Node] = [], code: [Node] = []
        for radio in radios {
            guard let names = labels(radio) else { return nil }
            let isChat = names.contains("Chat and Cowork"), isCode = names.contains("Code")
            guard isChat != isCode else { return nil }
            if isChat { chat.append(radio) } else { code.append(radio) }
        }
        guard chat.count == 1, code.count == 1 else { return nil }
        return (chat[0], code[0])
    }
}
