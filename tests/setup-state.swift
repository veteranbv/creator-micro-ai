import Foundation

@main
enum SetupTests {
    static func main() {
        let home = URL(fileURLWithPath: "/tmp/setup-fixture-home")
        precondition(SetupState.isInstalled(at: home.appendingPathComponent("Applications/Creator Micro AI.app"), home: home))
        precondition(SetupState.isInstalled(at: URL(fileURLWithPath: "/Applications/Creator Micro AI.app"), home: home))
        for path in ["Downloads/Creator Micro AI.app", "Applications/Claude.app", "Applications/Creator Micro AI.app/Contents"] {
            precondition(!SetupState.isInstalled(at: home.appendingPathComponent(path), home: home))
        }
        var state = SetupState()
        precondition(state.canContinue && !state.canFinish)
        for step in SetupState.Step.allCases where step != .welcome {
            state.step = step
            precondition(!state.canContinue)
        }
        state.appsReady = true
        state.step = .permissions
        state.accessibility = true
        precondition(!state.canContinue, "Both permissions are required")
        state.inputMonitoring = true
        precondition(state.canContinue)
        state.step = .profile
        state.connected = true
        precondition(!state.canContinue, "Connection does not prove the profile matches")
        state.profileMatches = true
        precondition(state.canContinue && !state.canFinish)
        state.dictationConfirmed = true
        state.wiredConfirmed = true
        state.controlsConfirmed = true
        state.step = .ready
        precondition(state.canFinish, "Bluetooth is optional, not silently passed")
        state.busy = true
        precondition(!state.canFinish && !state.canContinue)
        state.busy = false
        let saved = state.saved(build: "test-build")
        precondition(Set(saved.keys) == ["step", "build", "dictation", "wired", "bluetooth", "controls"])
        state.restore(saved, build: "test-build")
        precondition(state.step == .ready && state.controlsConfirmed && state.wiredConfirmed)
        precondition(!state.accessibility && !state.inputMonitoring && !state.connected && !state.profileMatches)
        precondition(!state.canFinish, "Restoring progress cannot restore live checks")
        state.restore(saved, build: "different-build")
        precondition(state.step == .welcome && !state.controlsConfirmed && !state.wiredConfirmed)
        state.restore(["build": "test-build", "step": 999], build: "test-build")
        precondition(state.step == .welcome)
        state.dictationConfirmed = true; state.wiredConfirmed = true; state.bluetoothConfirmed = true; state.controlsConfirmed = true
        state.invalidatePhysicalChecks()
        precondition(!state.dictationConfirmed && !state.wiredConfirmed && !state.bluetoothConfirmed && !state.controlsConfirmed)

        func decode(_ value: String, success: Bool = true) -> SetupDeviceOperation.Result {
            SetupDeviceOperation.decode(Data(value.utf8), success: success)
        }
        let completed = "{\"type\":\"complete\",\"matches\":true}\n"
        precondition(decode(completed).matches && decode(completed).succeeded)
        precondition(!decode(completed, success: false).succeeded)
        let different = decode("{\"type\":\"complete\",\"matches\":false}\n")
        precondition(different.succeeded && !different.matches)
        for invalid in ["", "{}", "garbage\n" + completed, completed + completed,
                        "{\"type\":\"failed\"}\n" + completed,
                        "{\"type\":\"complete\",\"matches\":1}\n",
                        "{\"type\":\"complete\",\"matches\":true,\"extra\":1}\n"] {
            precondition(!decode(invalid).succeeded)
        }
        let backup = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Creator Micro AI/backups/device-fixture/keymap.before.json").path
        func event(_ path: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: ["type": "backup", "file": path])
            return String(decoding: data, as: UTF8.self) + "\n"
        }
        let recovered = decode(event(backup) + "{\"type\":\"failed\"}\n", success: false)
        precondition(!recovered.succeeded && recovered.backup?.path == backup,
                     "A failed write must preserve the safe recovery location")
        precondition(decode(event(backup) + completed).succeeded)
        for invalid in ["relative/keymap.before.json", "/tmp/keymap.before.json", backup + "/../../../../keymap.before.json"] {
            let result = decode(event(invalid) + completed)
            precondition(!result.succeeded && result.backup == nil)
        }
        precondition(!decode(event(backup) + event(backup) + completed).succeeded)
        precondition(!decode(completed + event(backup)).succeeded)
        print("PASS: setup gates, build-scoped progress, independent permissions, protocol failures and private recovery paths. No device access.")
    }
}
