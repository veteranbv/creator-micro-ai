import Foundation
import ApplicationServices

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
        for status: AXError in [.cannotComplete, .invalidUIElement, .failure] {
            check(ControllerTargetPolicy.attributeValue(status: status, value: "AXGroup", absent: "") == nil,
                  "attribute error cannot hide a permission container")
        }
        check(ControllerTargetPolicy.attributeValue(status: .success, value: Optional<String>.none, absent: "") == nil,
              "wrong attribute type is incomplete evidence")
        check(ControllerTargetPolicy.attributeValue(status: .attributeUnsupported, value: Optional<String>.none, absent: "") == "",
              "unsupported optional attribute is absent")
        check(ControllerTargetPolicy.attributeValue(status: .noValue, value: Optional<String>.none, absent: "") == "",
              "optional attribute with no value is absent")
        check(ControllerTargetPolicy.attributeValue(status: .success, value: "AXGroup", absent: "") == "AXGroup",
              "successful attribute retains its value")
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
        for claude in [false, true] {
            for approve in [false, true] {
                let permitted = approve ? "Allow once" : "Deny"
                check(ControllerTargetPolicy.isApprovalLabels([permitted, "", permitted], claude: claude, approve: approve),
                      "consistent action labels are accepted")
                for labels in [[permitted, "Always allow"], [permitted, "Always allow 2"], ["Allow once", "Deny"],
                               [permitted, "unrecognized action"], [], [""]] {
                    check(!ControllerTargetPolicy.isApprovalLabels(labels, claude: claude, approve: approve),
                          "conflicting or unknown approval labels fail closed")
                }
            }
        }
        check(ControllerTargetPolicy.isApprovalLabels(["Allow once", "Allow once 3"], claude: true, approve: true),
              "Claude numbered labels still identify the same one-time action")
        check(!ControllerTargetPolicy.isApprovalLabels(["Allow once", "Allow once 3"], claude: false, approve: true),
              "Claude numbering is not inferred for ChatGPT")
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
        check(pair.approval([1], [1]) == nil, "Y rejects a single control labeled both Allow once and Deny")
        check(pair.approval([1], [1], approve: false) == nil, "X rejects a single control labeled both actions")
        let incompletePair = ControllerTargetPolicy.pairedApproval(approvals: [1], declines: [2], approve: true,
            parent: { _ in 0 }, group: { _, _ -> [Int]? in nil }, equal: ==)
        check(incompletePair == nil, "an unreadable pair ancestor cannot establish uniqueness")
        check(ControllerTargetPolicy.claudePermissionContents(requests: [0], group: { _, _ -> [Int]? in nil }).isEmpty,
              "unreadable Claude permission contents fail closed")
        func complete(_ unreadable: Set<Int> = [], limit: Int = 100) -> [Int]? {
            ControllerTargetPolicy.completeDescendants(0, limit: limit, children: {
                unreadable.contains($0) ? nil : [0: [1, 4], 1: [2, 3]][$0] ?? []
            })
        }
        check(complete() == [0, 1, 2, 3, 4], "complete traversal includes the sibling after a permission pair")
        check(complete([4]) == nil, "unreadable sibling cannot hide a conflicting permission card")
        let copyFromIncompleteTree = complete([4]).flatMap { $0.last }
        check(copyFromIncompleteTree == nil, "an unreadable newest response cannot select an older Copy target")
        check(complete([0]) == nil, "unreadable window fails closed")
        check(complete(limit: 5) == nil, "traversal budget cannot return a partial candidate list")
        check(ControllerTargetPolicy.childValues(status: .success, values: [Int]()) == [], "empty child array is a leaf")
        check(ControllerTargetPolicy.childValues(status: .attributeUnsupported, values: [Int]?.none) == [],
              "unsupported children attribute is a leaf")
        check(ControllerTargetPolicy.childValues(status: .noValue, values: [Int]?.none) == [],
              "children attribute without a value is a leaf")
        for status in [AXError.cannotComplete, .invalidUIElement, .failure, .notImplemented] {
            check(ControllerTargetPolicy.childValues(status: status, values: [Int]?.none) == nil,
                  "AX read failures remain distinguishable from leaves")
        }
        check(ControllerTargetPolicy.childValues(status: .success, values: [Int]?.none) == nil,
              "malformed successful children response fails closed")

        // Synthetic permission card: alert/header and form/buttons are direct siblings.
        let cardTree = Tree(children: [0: [1, 20], 1: [2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 20: [21, 22]])
        let formClasses = ["flex", "@max-md/approval-card:flex-col", "@max-md/approval-card:items-stretch"]
        check(ControllerTargetPolicy.isOpenAIApprovalForm(formClasses), "recognizes the observed approval form classes")
        check(!ControllerTargetPolicy.isOpenAIApprovalForm(["relative", "flex", "flex-col", "gap-2"]),
              "generic layout classes do not identify an approval form")
        func openAIButtons(_ tree: Tree = cardTree, alerts: Set<Int> = [2], headers: Set<Int> = [4],
            forms: Set<Int> = [3], buttons: Set<Int> = [7, 8, 9, 21, 22],
            unreadable: Set<Int> = []) -> [Int] {
            ControllerTargetPolicy.openAIPermissionButtons(nodes: tree.group(0, 5000),
                children: { unreadable.contains($0) ? nil : tree.children[$0] ?? [] },
                isGroup: { tree.children[$0] != nil }, isAlert: { alerts.contains($0) },
                isPermissionsText: { headers.contains($0) }, isForm: { forms.contains($0) },
                isButton: { buttons.contains($0) })
        }
        let scoped = openAIButtons()
        let names = [7: "Deny", 8: "Allow once", 9: "Approval options", 21: "Deny", 22: "Allow once"]
        let scopedYes = scoped.filter { names[$0] == "Allow once" }
        let scopedNo = scoped.filter { names[$0] == "Deny" }
        check(scoped == [7, 8, 9], "ChatGPT scopes controls to the sibling approval form")
        check(cardTree.approval(scopedYes, scopedNo) == 8, "ChatGPT Y ignores same-named buttons outside the card")
        check(cardTree.approval(scopedYes, scopedNo, approve: false) == 7,
              "ChatGPT X ignores same-named buttons outside the card")
        check(!scopedYes.contains(9), "ChatGPT Y never opens Approval options")
        check(openAIButtons(alerts: []).isEmpty, "ChatGPT rejects a card without the application alert")
        check(openAIButtons(headers: []).isEmpty, "ChatGPT rejects an alert without the Permissions text")
        check(openAIButtons(forms: []).isEmpty, "ChatGPT rejects a card without the marked form")
        check(openAIButtons(unreadable: [1]).isEmpty, "ChatGPT rejects unreadable card children")
        check(openAIButtons(unreadable: [2]).isEmpty, "ChatGPT rejects unreadable alert children")
        check(openAIButtons(unreadable: [3]).isEmpty, "ChatGPT rejects unreadable form children")
        check(openAIButtons(buttons: [7, 9, 21, 22]).isEmpty, "ChatGPT rejects a disabled or non-button action")
        let textOnly = Tree(children: [0: [20], 20: [21, 22]])
        check(openAIButtons(textOnly).isEmpty, "ChatGPT rejects unrelated Allow once and Deny buttons")
        let split = Tree(children: [0: [1, 20], 1: [2], 2: [4, 5, 6], 20: [3], 3: [7, 8, 9]])
        check(openAIButtons(split).isEmpty, "ChatGPT rejects an alert and form in different cards")
        let nested = Tree(children: [0: [1], 1: [2, 10], 2: [4, 5, 6], 10: [3], 3: [7, 8, 9]])
        check(openAIButtons(nested).isEmpty, "ChatGPT does not guess through an unrecognized form wrapper")
        let multiple = Tree(children: [0: [1, 11], 1: [2, 3], 2: [4], 3: [7, 8, 9],
                                      11: [12, 13], 12: [14], 13: [17, 18]])
        check(openAIButtons(multiple, alerts: [2, 12], headers: [4, 14], forms: [3, 13],
                            buttons: [7, 8, 9, 17, 18]).isEmpty,
              "ChatGPT rejects multiple permission alerts instead of choosing a card")
        let incompleteSecond = Tree(children: [0: [1, 12], 1: [2, 3], 2: [4], 3: [7, 8, 9], 12: [14]])
        check(openAIButtons(incompleteSecond, alerts: [2, 12], headers: [4, 14]).isEmpty,
              "ChatGPT rejects a second Permissions alert even without its action form")
        let twoActions = Tree(children: [0: [1], 1: [2, 3], 2: [4], 3: [7, 8]])
        check(openAIButtons(twoActions) == [7, 8], "ChatGPT permits the form without the optional dropdown")
        let extraChild = Tree(children: [0: [1], 1: [2, 3, 10], 2: [4], 3: [7, 8, 9]])
        check(openAIButtons(extraChild).isEmpty, "ChatGPT rejects an unrecognized card structure")
        let missingAction = Tree(children: [0: [1], 1: [2, 3], 2: [4], 3: [8]])
        check(openAIButtons(missingAction).isEmpty, "ChatGPT rejects a partial action form")

        print("\(count) target-selection fixture checks passed")
    }
}
