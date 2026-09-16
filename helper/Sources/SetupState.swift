import Foundation

// Only explicit setup choices persist. Live trust and device checks never do.
struct SetupState {
    enum Step: Int, CaseIterable {
        case welcome, apps, permissions, profile, dictation, practice, ready
        var title: String {
            ["Welcome", "Your apps", "Permissions", "Your device", "Dictation", "Try it", "Ready"][rawValue]
        }
    }

    var step: Step = .welcome
    var appsReady = false
    var accessibility = false
    var inputMonitoring = false
    var connected = false
    var profileMatches = false
    var busy = false
    var dictationConfirmed = false
    var wiredConfirmed = false
    var bluetoothConfirmed = false
    var controlsConfirmed = false

    static func isInstalled(at url: URL, home: URL) -> Bool {
        let location = url.resolvingSymlinksInPath().standardizedFileURL
        return [URL(fileURLWithPath: "/Applications/Creator Micro AI.app"),
                home.appendingPathComponent("Applications/Creator Micro AI.app")]
            .contains { $0.resolvingSymlinksInPath().standardizedFileURL == location }
    }

    var permissionsReady: Bool { accessibility && inputMonitoring }
    var machineReady: Bool { appsReady && permissionsReady && connected && profileMatches && !busy }
    var canFinish: Bool { machineReady && dictationConfirmed && wiredConfirmed && controlsConfirmed }
    var canContinue: Bool {
        guard !busy else { return false }
        switch step {
        case .welcome: return true
        case .apps: return appsReady
        case .permissions: return appsReady && permissionsReady
        case .profile: return machineReady
        case .dictation: return machineReady && dictationConfirmed
        case .practice, .ready: return canFinish
        }
    }

    mutating func restore(_ values: [String: Any], build: String) {
        self = SetupState()
        step = Step(rawValue: values["step"] as? Int ?? 0) ?? .welcome
        // Physical confirmations belong to a build, never to a future update.
        guard values["build"] as? String == build else { step = .welcome; return }
        dictationConfirmed = values["dictation"] as? Bool ?? false
        wiredConfirmed = values["wired"] as? Bool ?? false
        bluetoothConfirmed = values["bluetooth"] as? Bool ?? false
        controlsConfirmed = values["controls"] as? Bool ?? false
    }

    func saved(build: String) -> [String: Any] {
        ["step": step.rawValue, "build": build, "dictation": dictationConfirmed,
         "wired": wiredConfirmed, "bluetooth": bluetoothConfirmed, "controls": controlsConfirmed]
    }

    mutating func invalidatePhysicalChecks() {
        dictationConfirmed = false
        wiredConfirmed = false
        bluetoothConfirmed = false
        controlsConfirmed = false
    }
}
