import Foundation

// Standalone fixture runner, matching the existing Swift executable tests.
// No helper instance, app inspection, hotkeys, clipboard access, or UI events.
@main
enum ControllerTargetTests {
    struct Tree {
        let children: [Int: [Int]]
        func parent(_ node: Int) -> Int? { children.first { $0.value.contains(node) }?.key }
        func group(_ node: Int, _ limit: Int) -> [Int] {
            var stack = [node], result: [Int] = []
            while let next = stack.popLast(), result.count < limit {
                result.append(next)
                stack.append(contentsOf: (children[next] ?? []).reversed())
            }
            return result
        }
        func approval(_ yes: [Int], _ no: [Int], approve: Bool = true) -> Int? {
            ControllerTargetPolicy.pairedApproval(approvals: yes, declines: no, approve: approve,
                parent: parent, group: group, equal: ==)
        }
    }
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        check(ControllerTargetPolicy.isOpenAIResponseGroup(["relative", "shrink-0"]),
              "recognizes a flattened response parent group")
        check(!ControllerTargetPolicy.isOpenAIResponseGroup(["turn-action-controls", "h-5"]),
              "does not mistake the absent DOM toolbar for the observed parent")
        func directCopy(_ children: [String]) -> String? {
            ControllerTargetPolicy.directResponseCopy(children: children,
                isAssistantHeading: { $0 == "ChatGPT said:" }, isUserHeading: { $0 == "You said:" },
                isCopy: { ["Copy", "Copied"].contains($0) })
        }
        check(directCopy(["You said:", "attachment", "10:00 AM", "Copy message", "Worked for 1m",
                          "ChatGPT said:", "status", "body group", "nested code group", "Copy", "10:01 AM"]) == "Copy",
              "copies assistant response in the flattened accessibility layout")
        check(directCopy(["You said:", "Copy message"]) == nil, "user prompt cannot qualify as a response")
        check(directCopy(["ChatGPT said:", "nested code group"]) == nil, "does not descend into code-block Copy buttons")
        check(directCopy(["ChatGPT said:", "Copy", "You said:", "ChatGPT said:", "body group"]) == nil,
              "incomplete latest response cannot fall back to earlier Copy")
        check(directCopy(["ChatGPT said:", "Copy", "You said:", "ChatGPT said:", "Copied"]) == "Copied",
              "latest copied state blocks falling back to previous response")
        check(directCopy(["ChatGPT said:", "body group", "You said:", "Copy"]) == nil,
              "does not cross into a later user section")
        check(directCopy(["ChatGPT said:", "Copy", "Copy"]) == nil, "multiple direct Copy buttons fail closed")
        for name in ["Message 132", "Message 2 of 2", "Message 1 of 25"] {
            check(ControllerTargetPolicy.isClaudeMessageName(name), "recognizes \(name)")
        }
        for name in ["Message actions", "Message ", "Message 2 unrelated", "Message 0", "Message 3 of 2"] {
            check(!ControllerTargetPolicy.isClaudeMessageName(name), "rejects non-message label \(name)")
        }
        check(ControllerTargetPolicy.isClaudeActionReveal("Show message actions"), "recognizes compact action reveal")
        check(ControllerTargetPolicy.isClaudeActionReveal("Show message actions for Claude responded: Example"),
              "recognizes contextual assistant action reveal")
        check(!ControllerTargetPolicy.isClaudeActionReveal("Show message actions for You said: Example"),
              "rejects user-message action reveal")
        let pair = Tree(children: [0: [1], 1: [2, 3, 4]])
        for name in ["Allow once", "Allow once 2", "Allow once 3"] {
            check(ControllerTargetPolicy.isClaudeApprovalName(name, approve: true), "Claude recognizes \(name)")
        }
        for name in ["Deny", "Deny 1"] {
            check(ControllerTargetPolicy.isClaudeApprovalName(name, approve: false), "Claude recognizes \(name)")
        }
        for name in ["Always allow", "Always allow 2", "Allow once 20", "Allow once 30", "Deny 10", "Allow", ""] {
            check(!ControllerTargetPolicy.isClaudeApprovalName(name, approve: true)
                  && !ControllerTargetPolicy.isClaudeApprovalName(name, approve: false),
                  "Claude rejects unsupported approval label \(name)")
        }
        check(!ControllerTargetPolicy.isClaudeApprovalName("Deny 1", approve: true), "Y never selects Claude Deny")
        check(!ControllerTargetPolicy.isClaudeApprovalName("Allow once 3", approve: false), "X never selects Claude Allow once")
        func claudeContents(_ requests: [Int]) -> [Int] {
            ControllerTargetPolicy.claudePermissionContents(requests: requests, group: pair.group)
        }
        check(claudeContents([]).isEmpty, "Claude requires a permission panel")
        check(claudeContents([1, 0]).isEmpty, "multiple Claude permission panels fail closed")
        check(claudeContents([1]) == [1, 2, 3, 4], "Claude matching stays inside the permission panel")
        let numberedNames = [2: "Allow once 3", 3: "Deny 1", 4: "Always allow 2"]
        let numberedYes = claudeContents([1]).filter {
            ControllerTargetPolicy.isClaudeApprovalName(numberedNames[$0] ?? "", approve: true)
        }
        let numberedNo = claudeContents([1]).filter {
            ControllerTargetPolicy.isClaudeApprovalName(numberedNames[$0] ?? "", approve: false)
        }
        check(pair.approval(numberedYes, numberedNo) == 2, "Claude numbered panel selects Allow once")
        check(pair.approval(numberedYes, numberedNo, approve: false) == 3, "Claude numbered panel selects Deny")
        let twoButtonTree = Tree(children: [0: [1], 1: [2, 3]])
        let twoButtonNames = [2: "Allow once 2", 3: "Deny 1"]
        let twoButtonContents = ControllerTargetPolicy.claudePermissionContents(requests: [1], group: twoButtonTree.group)
        let twoButtonYes = twoButtonContents.filter {
            ControllerTargetPolicy.isClaudeApprovalName(twoButtonNames[$0] ?? "", approve: true)
        }
        let twoButtonNo = twoButtonContents.filter {
            ControllerTargetPolicy.isClaudeApprovalName(twoButtonNames[$0] ?? "", approve: false)
        }
        check(twoButtonTree.approval(twoButtonYes, twoButtonNo) == 2, "Claude two-button panel selects renumbered Allow once")
        check(twoButtonTree.approval(twoButtonYes, twoButtonNo, approve: false) == 3, "Claude two-button panel still selects Deny")
        check(!ControllerTargetPolicy.isClaudeApprovalName("Allow once 2", approve: false), "X never selects renumbered Allow once")
        let largeRequest = Tree(children: [0: Array(1...101)])
        check(ControllerTargetPolicy.claudePermissionContents(requests: [0], group: largeRequest.group).isEmpty,
              "truncated Claude permission panel fails closed")
        check(pair.approval([], []) == nil, "no request is a no-op")
        check(pair.approval([2], []) == nil, "no Deny partner is a no-op")
        check(pair.approval([], [3]) == nil, "no Allow once partner is a no-op")
        check(pair.approval([2], [3]) == 2, "Y selects one-time approval")
        check(pair.approval([2], [3], approve: false) == 3, "X selects Deny")
        check(pair.approval([2, 4], [3]) == nil, "multiple approvals are ambiguous")
        check(pair.approval([2], [3, 4]) == nil, "multiple declines are ambiguous")
        check(pair.approval([], [3]) != 4, "Always allow is never an approval candidate")
        let unrelated = Tree(children: [0: Array(1...110)])
        check(unrelated.approval([1], [2]) == nil, "oversized shared window is not a request card")
        let disconnected = Tree(children: [0: [1], 3: [4]])
        check(disconnected.approval([1], [4]) == nil, "disconnected controls cannot pair")

        print("\(count) target-selection fixture checks passed")
    }
}
