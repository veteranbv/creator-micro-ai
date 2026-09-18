import Foundation

@main
enum HelperHealthTests {
    static func main() {
        var health = HelperHealth(now: 100)
        precondition(health.connection == .waiting)
        precondition(health.needsAttention)
        health.accessibilityTrusted = true
        precondition(health.needsAttention, "Accessibility does not replace Input Monitoring")
        precondition(health.inputMonitoringTitle == "Input Monitoring: permission required")
        health.inputMonitoringTrusted = true
        precondition(health.inputMonitoringTitle == "Input Monitoring: trusted")
        precondition(!health.needsAttention)
        health.checkStartup(now: 107.9)
        precondition(health.connection == .waiting)
        health.checkStartup(now: 108)
        precondition(health.connection == .unavailable && health.needsAttention)

        health.receive(type: "layer", layer: 1)
        precondition(health.connection == .unavailable, "A layer cannot replace the ready handshake")
        health.receive(type: "ready", layer: nil)
        precondition(health.connection == .unavailable)
        health.receive(type: "ready", layer: 5)
        precondition(health.connection == .unavailable)
        health.receive(type: "ready", layer: 1)
        precondition(health.connection == .connected && !health.needsAttention)
        health.checkStartup(now: 1000)
        precondition(health.connection == .connected)

        health.beginSwitch()
        precondition(health.switching == .pending)
        health.finishSwitch(success: false)
        precondition(health.needsAttention && health.connection == .connected)
        health.beginSwitch()
        health.finishSwitch(success: true)
        precondition(!health.needsAttention)
        precondition(health.switchingTitle == "Workspace switch: request sent")

        health.beginSwitch()
        health.receive(type: "error", layer: nil)
        health.bridgeFailed(.crashed)
        precondition(health.connectionTitle == "Device bridge: crashed; retrying within 30 seconds")
        precondition(health.needsAttention && health.connection == .unavailable)
        precondition(health.switching == .failed, "A disconnected pending switch cannot stay in progress")
        precondition(health.accessibilityTrusted, "USB failure does not diagnose Accessibility")
        health.receive(type: "applied", layer: 2)
        precondition(health.connection == .unavailable)
        health.receive(type: "ready", layer: 2)
        precondition(health.bridgeFailure == nil)
        precondition(health.needsAttention, "Reconnect alone does not prove a failed switch succeeded")
        health.beginSwitch()
        health.finishSwitch(success: true)
        precondition(!health.needsAttention)
        health.receive(type: "error", layer: nil)
        health.bridgeFailed(.launchFailed)
        precondition(health.connectionTitle.contains("could not launch"))
        health.bridgeFailed(.exited)
        precondition(health.connectionTitle.contains("restarting after connection failure"))
        health.receive(type: "ready", layer: 2)
        health.accessibilityTrusted = false
        precondition(health.needsAttention && health.connection == .connected)
        precondition(health.accessibilityTitle == "Accessibility: permission required")
        health.accessibilityTrusted = true
        health.inputMonitoringTrusted = false
        precondition(health.needsAttention && health.connection == .connected)
        health.inputMonitoringTrusted = true
        precondition(!health.needsAttention)
        print("PASS: startup timeout, ready validation, disconnect/recovery, independent permissions and switch status. No device access.")
    }
}
