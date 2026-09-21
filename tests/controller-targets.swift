import Foundation
import ApplicationServices

// Standalone fixture runner, matching the existing Swift executable tests.
// Attribute reads are injected. No app inspection, hotkeys, clipboard access, or UI events.
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
        // AX elements are opaque fixture identities; the injected reader never calls macOS.
        let fixtureNodes = (1...32).map { AXUIElementCreateApplication(pid_t($0)) }
        func reader(failureNode: Int? = nil, failureKey: String = kAXTitleAttribute,
                    failure: AXError = .cannotComplete, searchName: String = "Search") -> ControllerAccessibility {
            ControllerAccessibility { element, key in
                let index = fixtureNodes.firstIndex { CFEqual($0, element) }!
                if index == failureNode && key == failureKey { return (failure, nil) }
                if key == kAXChildrenAttribute {
                    let tree = [0: [7, 5, 6], 7: [1, 3], 1: [2], 3: [4]]
                    return (.success, (tree[index] ?? []).map { fixtureNodes[$0] } as CFArray)
                }
                if key == kAXTitleAttribute {
                    let names = [1: "Message 1", 2: "Claude responded: Earlier", 3: "Message 2",
                                 4: "Claude responded: Latest", 5: searchName, 6: "Other", 7: "Chat messages"]
                    return (.success, (names[index] ?? "") as CFString)
                }
                if key == kAXRoleAttribute {
                    let role = [2, 4].contains(index) ? "AXHeading" : ([5, 6].contains(index) ? kAXButtonRole : kAXGroupRole)
                    return (.success, role as CFString)
                }
                if key == kAXEnabledAttribute { return (.success, kCFBooleanTrue) }
                return (.attributeUnsupported, nil)
            }
        }
        let actions = ControllerActions()
        check(CFEqual(actions.latestClaudeMessage(fixtureNodes[0], using: reader())!, fixtureNodes[3]),
              "real Copy selector chooses the newest synthetic assistant message")
        for failedNode in [3, 4] {
            for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                for error in [AXError.cannotComplete, .invalidUIElement, .failure, .success] {
                    check(actions.latestClaudeMessage(fixtureNodes[0], using: reader(failureNode: failedNode, failureKey: key, failure: error)) == nil,
                          "unreadable or malformed newest message label never falls back to older response")
                }
            }
        }
        // Synthetic unnumbered Code response: transcript > body > final response > actions.
        func claudeReader(tree: [Int: [Int]] = [0: [1], 1: [2], 2: [3, 4], 4: [5], 5: [6, 7]],
                          names: [Int: String] = [:], roles: [Int: String] = [:],
                          disabled: Set<Int> = [], failureNode: Int? = nil,
                          failureKey: String = kAXChildrenAttribute,
                          failure: AXError = .cannotComplete) -> ControllerAccessibility {
            ControllerAccessibility { element, key in
                let index = fixtureNodes.firstIndex { CFEqual($0, element) }!
                if index == failureNode && key == failureKey { return (failure, nil) }
                if key == kAXChildrenAttribute {
                    return (.success, (tree[index] ?? []).map { fixtureNodes[$0] } as CFArray)
                }
                if key == kAXTitleAttribute {
                    let defaults = [1: "Chat messages", 5: "Message actions", 6: "Copy", 7: "Read aloud"]
                    return (.success, (names[index] ?? defaults[index] ?? "") as CFString)
                }
                if key == kAXRoleAttribute {
                    let defaults = [3: kAXStaticTextRole, 5: kAXToolbarRole, 6: kAXButtonRole, 7: kAXButtonRole]
                    return (.success, (roles[index] ?? defaults[index] ?? kAXGroupRole) as CFString)
                }
                if key == kAXEnabledAttribute { return (.success, disabled.contains(index) ? kCFBooleanFalse : kCFBooleanTrue) }
                return (.attributeUnsupported, nil)
            }
        }
        check(actions.latestClaudeMessage(fixtureNodes[0], using: claudeReader()).map { CFEqual($0, fixtureNodes[4]) } == true,
              "unnumbered Code response is found inside Chat messages")
        func claudeCopy(_ reads: ControllerAccessibility) -> AXUIElement? {
            guard let message = actions.latestClaudeMessage(fixtureNodes[0], using: reads) else { return nil }
            return actions.claudeCopyControl(message, using: reads)
        }
        check(claudeCopy(claudeReader()).map { CFEqual($0, fixtureNodes[6]) } == true,
              "unnumbered assistant toolbar selects its full-response Copy")
        let numberedTree = [0: [1], 1: [2], 2: [3, 4], 4: [8, 5], 5: [6, 7]]
        for messageName in ["Message 24", "Message 24 of 24"] {
            check(claudeCopy(claudeReader(tree: numberedTree,
                names: [4: messageName, 8: "Claude responded: Example"], roles: [8: "AXHeading"]))
                .map { CFEqual($0, fixtureNodes[6]) } == true, "numbered Code and Chat responses remain supported")
            check(claudeCopy(claudeReader(tree: numberedTree,
                names: [4: messageName, 8: "Claude responded: Example", 7: "Stop reading"], roles: [8: "AXHeading"])) != nil,
                "known assistant heading does not depend on Read aloud playback state")
            check(claudeCopy(claudeReader(tree: numberedTree,
                names: [4: messageName, 8: "You said: Example"], roles: [8: "AXHeading"])) == nil,
                "latest numbered user message cannot select an earlier response")
        }
        let revealReads = claudeReader(tree: [0: [1], 1: [2], 2: [3, 4], 4: [9]],
            names: [9: "Show message actions"], roles: [9: kAXButtonRole])
        let revealMessage = actions.latestClaudeMessage(fixtureNodes[0], using: revealReads)
        check(revealMessage != nil && CFEqual(revealMessage!, fixtureNodes[4]),
              "hidden unnumbered toolbar retains the same response identity")
        check(actions.claudeActionReveal(revealMessage!, using: revealReads)
            .map { CFEqual($0, fixtureNodes[9]) } == true, "unique reveal is scoped to the newest body")
        check(actions.claudeCopyControl(revealMessage!, using: revealReads) == nil,
              "hidden toolbar is not mistaken for Copy")
        check(claudeCopy(claudeReader(tree: [0: [10], 10: [1], 1: [2], 2: [3, 4], 4: [5], 5: [6, 7]],
            names: [10: "Chat messages"])) != nil, "nested live-region transcript wrappers are accepted")
        check(claudeCopy(claudeReader(tree: [0: [10, 1], 1: [2], 2: [3, 4], 4: [5], 5: [6, 7]],
            names: [10: "Chat messages"])) == nil, "separate conversation panes are ambiguous")
        for terminal in ["Loading", "Message 25", "Unknown new layout"] {
            check(claudeCopy(claudeReader(tree: [0: [1], 1: [2], 2: [4, 10], 4: [5], 5: [6, 7]],
                names: [10: terminal])) == nil, "unsupported newest content never selects an older toolbar")
        }
        check(claudeCopy(claudeReader(tree: [0: [1], 1: [2], 2: [10, 4], 10: [11], 11: [12, 13],
            4: [5], 5: [6, 7]], names: [11: "Message actions", 12: "Copy", 13: "Read aloud"],
            roles: [11: kAXToolbarRole, 12: kAXButtonRole, 13: kAXButtonRole]))
            .map { CFEqual($0, fixtureNodes[6]) } == true, "older visible toolbar does not compete with the newest response")
        check(claudeCopy(claudeReader(tree: [0: [1], 1: [2], 2: [4], 4: [10, 5], 10: [11], 5: [6, 7]],
            names: [10: "Edited files", 11: "Copy"], roles: [11: kAXButtonRole]))
            .map { CFEqual($0, fixtureNodes[6]) } == true, "file panels and body Copy controls do not compete with the toolbar")
        for name in ["Rewind to here", "Fork from here", "Copied", ""] {
            check(claudeCopy(claudeReader(names: [7: name])) == nil,
                  "unnumbered toolbar without assistant evidence is rejected")
        }
        for name in ["Copy code", "Copied", "Copy message"] {
            check(claudeCopy(claudeReader(names: [6: name])) == nil, "only full-response Copy qualifies")
        }
        for disabled: Set<Int> in [[6], [7]] {
            check(claudeCopy(claudeReader(disabled: disabled)) == nil, "disabled unnumbered toolbar evidence fails closed")
        }
        for name in ["Copy", "Read aloud"] {
            check(claudeCopy(claudeReader(tree: [0: [1], 1: [2], 2: [4], 4: [5], 5: [6, 7, 8]],
                names: [8: name], roles: [8: kAXButtonRole])) == nil, "duplicate toolbar controls fail closed")
        }
        check(claudeCopy(claudeReader(tree: [0: [1], 1: [2], 2: [4], 4: [8, 5], 5: [6, 7]],
            names: [8: "Message actions"], roles: [8: kAXToolbarRole])) == nil, "multiple toolbars within one response are ambiguous")
        for node in [1, 2, 4, 5, 6, 7] {
            for key in [kAXChildrenAttribute, kAXRoleAttribute, kAXTitleAttribute] {
                for error in [AXError.cannotComplete, .invalidUIElement, .success] {
                    check(claudeCopy(claudeReader(failureNode: node, failureKey: key, failure: error)) == nil,
                          "unreadable Claude structure never supplies a Copy target")
                }
            }
        }
        check(claudeCopy(claudeReader(tree: [0: [1], 1: [2], 2: [2, 4], 4: [5], 5: [6, 7]])) == nil,
              "cyclic or truncated transcript fails within the traversal bound")
        for name in ["Search", "Model: Example"] {
            let clean = reader(searchName: name)
            check(CFEqual(clean.uniqueControl(in: clean.descendants(fixtureNodes[0])!, matching: { $0 == name })!, fixtureNodes[5]),
                  "complete model/search evidence selects one control")
            for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXRoleAttribute, kAXEnabledAttribute] {
                let broken = reader(failureNode: 6, failureKey: key, searchName: name)
                check(broken.uniqueControl(in: broken.descendants(fixtureNodes[0])!, matching: { $0 == name }) == nil,
                      "unreadable competing model/search control cannot establish uniqueness")
            }
            let broken = reader(failureNode: 6, failureKey: kAXChildrenAttribute, searchName: name)
            check(broken.descendants(fixtureNodes[0]) == nil && !broken.complete,
                  "unreadable model/search subtree cannot establish uniqueness")
        }
        let sticky = reader(failureNode: 6)
        _ = sticky.labels(fixtureNodes[6])
        _ = sticky.labels(fixtureNodes[5])
        check(!sticky.complete, "successful later label reads cannot erase an earlier failure")
        for status: AXError in [.attributeUnsupported, .noValue] {
            for key in [kAXRoleAttribute, kAXEnabledAttribute] {
                let absent = reader(failureNode: 6, failureKey: key, failure: status)
                check(absent.uniqueControl(in: absent.descendants(fixtureNodes[0])!, matching: { $0 == "Search" }) == nil,
                      "missing required role or enabled state cannot hide a competing control")
            }
            let missingContainer = reader(failureNode: 0, failureKey: kAXRoleAttribute, failure: status)
            _ = missingContainer.role(fixtureNodes[0])
            check(!missingContainer.complete, "missing container role invalidates discovery")
            check(ControllerTargetPolicy.attributeValue(status: status, value: Optional<String>.none, absent: "", required: true) == nil,
                  "required attributes reject absent status")
        }
        let emptyRole = ControllerAccessibility { _, _ in (.success, "" as CFString) }
        _ = emptyRole.role(fixtureNodes[0])
        check(!emptyRole.complete, "empty required role invalidates discovery")
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
                copyControl: { ["Copy", "Copied"].contains($0) ? $0 : nil })
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
        func openAIReader(newClasses: [String] = ["relative", "shrink-0"],
                          newChildren: [Int] = [5, 6], name: String = "Copy",
                          failureNode: Int? = nil, failureKey: String = kAXChildrenAttribute) -> ControllerAccessibility {
            ControllerAccessibility { element, key in
                let index = fixtureNodes.firstIndex { CFEqual($0, element) }!
                if index == failureNode && key == failureKey { return (.cannotComplete, nil) }
                if key == kAXChildrenAttribute {
                    let tree = [0: [1, 4], 1: [2, 3], 4: newChildren, 7: [8]]
                    return (.success, (tree[index] ?? []).map { fixtureNodes[$0] } as CFArray)
                }
                if key == kAXRoleAttribute {
                    return (.success, ([2, 5, 9].contains(index) ? "AXHeading" :
                        ([3, 6, 8].contains(index) ? kAXButtonRole : kAXGroupRole)) as CFString)
                }
                if key == kAXTitleAttribute {
                    return (.success, ([2: "ChatGPT said:", 3: "Copy", 5: "ChatGPT said: Latest", 6: name,
                                       8: "Copy", 9: "You said:"][index] ?? "") as CFString)
                }
                if key == "AXDOMClassList" {
                    return (.success, (index == 1 ? ["relative", "shrink-0"] :
                        (index == 4 ? newClasses : (index == 7 ? ["contents"] : []))) as CFArray)
                }
                if key == kAXEnabledAttribute { return (.success, kCFBooleanTrue) }
                return (.attributeUnsupported, nil)
            }
        }
        func newestOpenAICopy(_ reads: ControllerAccessibility) -> AXUIElement? {
            guard let all = reads.descendants(fixtureNodes[0]),
                  let children = actions.latestOpenAIResponse(in: all, using: reads) else { return nil }
            return actions.openAIResponseCopy(in: children, using: reads)
        }
        check(newestOpenAICopy(openAIReader()).map { CFEqual($0, fixtureNodes[6]) } == true,
              "whole-window selector uses the newest assistant heading")
        check(newestOpenAICopy(openAIReader(newChildren: [5, 7])).map { CFEqual($0, fixtureNodes[8]) } == true,
              "newest response retains observed one-child Copy wrapper support")
        for classes in [[], ["unknown-response"], ["relative"]] {
            check(newestOpenAICopy(openAIReader(newClasses: classes)) == nil,
                  "newest assistant heading in an unsupported group blocks older Copy")
        }
        for children in [[5], [5, 6, 7], [5, 9, 6]] {
            check(newestOpenAICopy(openAIReader(newChildren: children)) == nil,
                  "missing, ambiguous or user-section newest Copy never falls back")
        }
        for name in ["Copied", "Copy code"] {
            check(newestOpenAICopy(openAIReader(name: name)) == nil, "newest non-Copy state blocks older response")
        }
        for node in [4, 5, 6] {
            for key in [kAXChildrenAttribute, kAXRoleAttribute, kAXTitleAttribute] {
                // Container titles are not part of OpenAI response identity; DOM classes are.
                if node == 4 && key == kAXTitleAttribute { continue }
                check(newestOpenAICopy(openAIReader(failureNode: node, failureKey: key)) == nil,
                      "unreadable newest OpenAI evidence fails closed")
            }
        }
        check(newestOpenAICopy(openAIReader(failureNode: 4, failureKey: "AXDOMClassList")) == nil,
              "unreadable newest response classes do not permit older fallback")
        func copyReader(wrappedChildren: [Int] = [2], classes: [String] = ["contents"],
                        name: String = "Copy", enabled: Bool = true,
                        failureNode: Int? = nil, failureKey: String = kAXChildrenAttribute,
                        failure: AXError = .cannotComplete) -> ControllerAccessibility {
            ControllerAccessibility { element, key in
                let index = fixtureNodes.firstIndex { CFEqual($0, element) }!
                if index == failureNode && key == failureKey { return (failure, nil) }
                if key == kAXChildrenAttribute {
                    let children = index == 1 ? wrappedChildren : (index == 5 ? [6] : [])
                    return (.success, children.map { fixtureNodes[$0] } as CFArray)
                }
                if key == kAXRoleAttribute {
                    let role = [0, 3].contains(index) ? "AXHeading" : ([1, 5].contains(index) ? kAXGroupRole : kAXButtonRole)
                    return (.success, role as CFString)
                }
                if key == kAXTitleAttribute {
                    let names = [0: "ChatGPT said:", 3: "You said:", 2: name, 4: "Copy", 6: "Copy"]
                    return (.success, (names[index] ?? "") as CFString)
                }
                if key == "AXDOMClassList" { return (.success, (index == 1 ? classes : ["code-block"]) as CFArray) }
                if key == kAXEnabledAttribute { return (.success, (enabled ? kCFBooleanTrue : kCFBooleanFalse)) }
                return (.attributeUnsupported, nil)
            }
        }
        func responseCopy(_ children: [Int], _ reads: ControllerAccessibility? = nil) -> AXUIElement? {
            actions.openAIResponseCopy(in: children.map { fixtureNodes[$0] }, using: reads ?? copyReader())
        }
        check(responseCopy([0, 1]).map { CFEqual($0, fixtureNodes[2]) } == true,
              "observed contents wrapper resolves to its Copy button, not the group")
        check(responseCopy([0, 4]).map { CFEqual($0, fixtureNodes[4]) } == true,
              "unwrapped response Copy remains supported")
        check(responseCopy([0, 5, 1]).map { CFEqual($0, fixtureNodes[2]) } == true,
              "body code-block Copy is ignored beside the response wrapper")
        check(responseCopy([0, 5]) == nil, "code-block Copy alone is not response Copy")
        check(responseCopy([0, 1, 4]) == nil, "wrapped and direct Copy together are ambiguous")
        check(responseCopy([0, 1, 1]) == nil, "duplicate wrapped candidates fail closed")
        check(responseCopy([0, 4, 3, 0, 1], copyReader(name: "Copied")) == nil,
              "wrapped Copied state never falls back to an earlier response")
        check(responseCopy([0, 4, 3, 0, 5]) == nil, "missing newest Copy never uses an earlier response")
        check(responseCopy([0, 3, 1]) == nil, "wrapped Copy after a user heading is excluded")
        check(responseCopy([3, 1]) == nil, "user-only wrapper is excluded")
        for children in [[], [2, 6], [5]] {
            check(responseCopy([0, 1], copyReader(wrappedChildren: children)) == nil,
                  "empty, multi-child and nested wrappers are not searched")
        }
        for classes in [[], ["other"], ["contents", "code-block"]] {
            check(responseCopy([0, 1], copyReader(classes: classes)) == nil,
                  "only the observed contents-only wrapper is accepted")
        }
        check(responseCopy([0, 1], copyReader(enabled: false)) == nil, "disabled wrapped Copy is rejected")
        for name in ["Copy message", "Copy code", "Other"] {
            check(responseCopy([0, 1], copyReader(name: name)) == nil, "unrecognized wrapped control is rejected")
        }
        for error in [AXError.cannotComplete, .invalidUIElement, .failure, .success] {
            for key in [kAXChildrenAttribute, "AXDOMClassList", kAXRoleAttribute] {
                check(responseCopy([0, 1, 4], copyReader(failureNode: 1, failureKey: key, failure: error)) == nil,
                      "unreadable wrapper cannot hide a competing direct Copy")
            }
            for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXRoleAttribute, kAXEnabledAttribute] {
                check(responseCopy([0, 1, 4], copyReader(failureNode: 2, failureKey: key, failure: error)) == nil,
                      "unreadable wrapped Copy invalidates the selection")
            }
        }
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
