// Only the sidebar's Mode group identifies Claude's desktop workspace.
enum WorkspaceSelection {
    static func controls<Node>(root: Node, labels: (Node) -> [String],
        children: (Node) -> [Node], isRadio: (Node) -> Bool) -> (chat: Node, code: Node)? {
        var queue: [(Node, Int)] = [(root, 0)]
        var cursor = 0
        var sidebars: [Node] = []
        while cursor < queue.count {
            guard cursor < 100 else { return nil }
            let (node, depth) = queue[cursor]
            cursor += 1
            let names = labels(node)
            if names.contains("Sidebar") {
                sidebars.append(node)
                continue
            }
            // Do not inspect the conversation or composer when finding navigation.
            if names.contains("Primary pane") { continue }
            let next = children(node)
            guard next.isEmpty || depth < 10, queue.count + next.count <= 100 else { return nil }
            queue.append(contentsOf: next.map { ($0, depth + 1) })
        }
        guard sidebars.count == 1 else { return nil }
        let sidebarChildren = children(sidebars[0])
        guard sidebarChildren.count <= 100 else { return nil }
        let groups = sidebarChildren.filter { labels($0).contains("Mode") }
        guard groups.count == 1 else { return nil }
        let radios = children(groups[0])
        guard radios.count == 2, radios.allSatisfy(isRadio) else { return nil }
        let chat = radios.filter { labels($0).contains("Chat and Cowork") }
        let code = radios.filter { labels($0).contains("Code") }
        guard chat.count == 1, code.count == 1,
              !labels(chat[0]).contains("Code"), !labels(code[0]).contains("Chat and Cowork") else { return nil }
        return (chat[0], code[0])
    }
}
