import AppKit
import Darwin
import Foundation

@main
enum DeviceBridgeTests {
    static func until(_ description: String, timeout: TimeInterval = 8, _ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        precondition(done(), description)
    }

    static func fixture() -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "printf '%s\\n' '{\"type\":\"ready\",\"layer\":1}'; while IFS= read -r line; do :; done"]
        child.environment = [:]
        return child
    }

    static func main() {
        // The production class talks to a real child over pipes. No vendor code,
        // permission requests, keyboard events or device connections are used.
        var children: [Process] = [], failures: [HelperHealth.BridgeFailure] = []
        var readyCount = 0
        var health = HelperHealth()
        let bridge = DeviceBridge(makeProcess: {
            let child = fixture()
            children.append(child)
            return child
        })
        bridge.onFailure = { failures.append($0); health.bridgeFailed($0) }
        bridge.onMessage = {
            health.receive(type: $0.type, layer: $0.layer)
            if $0.type == "ready" { readyCount += 1 }
        }
        bridge.start()
        until("Initial ready handshake") { readyCount == 1 }
        precondition(bridge.focus(.codex) != nil)
        // SIGKILL exercises signal termination without generating a crash report.
        precondition(kill(children[0].processIdentifier, SIGKILL) == 0)
        until("Detect terminated child") { failures.count == 1 }
        precondition(failures[0] == .crashed)
        precondition(health.bridgeFailure == .crashed, "Synthetic error must not erase the process failure reason")
        for _ in 0..<100 { bridge.start() }
        precondition(children.count == 1, "Status refresh must not bypass backoff")
        until("Automatic restart without Reopen") { readyCount == 2 }
        precondition(children.count == 2 && children[1].isRunning)
        precondition(bridge.focus(.claude) != nil)
        var paused: Bool?
        bridge.pauseForSetup { paused = $0 }
        until("Setup pauses and reaps its child") { paused != nil }
        precondition(paused == true && !children[1].isRunning)
        precondition(failures.count == 1, "Intentional stop is not a crash")
        bridge.start()
        precondition(children.count == 2)
        bridge.resumeAfterSetup()
        until("Resume after setup") { readyCount == 3 }
        bridge.stop()
        until("Quit closes the child") { !children[2].isRunning }

        // A monotonic fake clock makes all backoff boundaries deterministic.
        var clock: TimeInterval = 100, launches = 0
        let missing = DeviceBridge(makeProcess: {
            launches += 1
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/nonexistent-bridge-fixture")
            return child
        }, now: { clock })
        var launchFailure: HelperHealth.BridgeFailure?
        missing.onFailure = { launchFailure = $0 }
        for (index, delay) in [3.0, 6, 12, 24, 30, 30].enumerated() {
            missing.start()
            precondition(launches == index + 1 && launchFailure == .launchFailed)
            clock += delay - 0.01
            for _ in 0..<20 { missing.start() }
            precondition(launches == index + 1)
            clock += 0.01
        }
        missing.stop()
        clock += 100
        missing.start()
        precondition(launches == 6, "Stopped bridge cannot restart")

        var stableChildren: [Process] = [], stableReady = 0, stableFailures = 0
        clock = 100
        let stable = DeviceBridge(makeProcess: {
            let child = fixture()
            stableChildren.append(child)
            return child
        }, now: { clock })
        stable.onMessage = { if $0.type == "ready" { stableReady += 1 } }
        stable.onFailure = { _ in stableFailures += 1 }
        for cycle in 0..<3 {
            stable.start()
            until("Ready for recovery cycle") { stableReady == cycle + 1 }
            if cycle == 2 { clock += 30 }
            precondition(kill(stableChildren[cycle].processIdentifier, SIGKILL) == 0)
            until("Observe cycle failure") { stableFailures == cycle + 1 }
            let delay = cycle == 1 ? 6.0 : 3.0
            clock += delay - 0.01
            stable.start()
            precondition(stableChildren.count == cycle + 1)
            clock += 0.01
        }
        stable.start()
        until("Healthy interval resets backoff") { stableReady == 4 }
        precondition(kill(stableChildren[3].processIdentifier, SIGKILL) == 0)
        until("Raise backoff before a healthy setup pause") { stableFailures == 4 }
        clock += 6
        stable.start()
        until("Ready before setup pause") { stableReady == 5 }
        clock += 30
        paused = nil
        stable.pauseForSetup { paused = $0 }
        until("Pause preserves the completed healthy interval") { paused != nil }
        precondition(paused == true && stableFailures == 4)
        stable.resumeAfterSetup()
        until("Ready after healthy pause") { stableReady == 6 }
        precondition(kill(stableChildren[5].processIdentifier, SIGKILL) == 0)
        until("Observe immediate failure after resume") { stableFailures == 5 }
        clock += 2.99
        stable.start()
        precondition(stableChildren.count == 6)
        clock += 0.01
        stable.start()
        until("Healthy pause resets recovery to three seconds") { stableReady == 7 }
        stable.stop()
        until("Final child stopped") { !stableChildren[6].isRunning }
        print("PASS: real child signal/restart, pipe delivery, bounded retry, healthy reset, setup pause/resume and quit. No device access.")
    }
}
