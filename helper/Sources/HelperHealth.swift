import Foundation

// Current state only. Never retain action history or vendor error text.
struct HelperHealth {
    enum Connection { case waiting, connected, unavailable }
    enum Switching { case idle, pending, sent, failed }
    enum BridgeFailure { case crashed, exited, launchFailed }

    private(set) var connection: Connection = .waiting
    private(set) var switching: Switching = .idle
    private(set) var bridgeFailure: BridgeFailure?
    var accessibilityTrusted = false
    var inputMonitoringTrusted = false
    private let startedAt: TimeInterval
    // Allow the bridge's five-second RPC deadline plus the parent's three-second retry.
    private static let startupGracePeriod: TimeInterval = 8

    init(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        startedAt = now
    }

    mutating func receive(type: String, layer: Int?) {
        switch type {
        case "ready":
            guard let layer, (1...4).contains(layer) else {
                connection = .unavailable
                return
            }
            connection = .connected
            bridgeFailure = nil
        case "error":
            connection = .unavailable
            bridgeFailure = nil
            if switching == .pending { switching = .failed }
        default:
            break
        }
    }

    mutating func checkStartup(now: TimeInterval) {
        if connection == .waiting, now - startedAt >= Self.startupGracePeriod {
            connection = .unavailable
        }
    }

    mutating func beginSwitch() { switching = .pending }
    mutating func bridgeFailed(_ reason: BridgeFailure) { bridgeFailure = reason }
    mutating func finishSwitch(success: Bool) { switching = success ? .sent : .failed }

    var needsAttention: Bool {
        !accessibilityTrusted || !inputMonitoringTrusted || connection == .unavailable || switching == .failed
    }

    var connectionTitle: String {
        switch connection {
        case .waiting: return "Device bridge: connecting"
        case .connected: return "Device bridge: connected"
        case .unavailable:
            switch bridgeFailure {
            case .crashed: return "Device bridge: crashed; retrying within 30 seconds"
            case .exited: return "Device bridge: restarting after connection failure"
            case .launchFailed: return "Device bridge: could not launch; check Input installation"
            case nil: return "Device bridge: unavailable; retrying"
            }
        }
    }

    var accessibilityTitle: String {
        accessibilityTrusted ? "Accessibility: trusted" : "Accessibility: permission required"
    }

    var inputMonitoringTitle: String {
        inputMonitoringTrusted ? "Input Monitoring: trusted" : "Input Monitoring: permission required"
    }

    var switchingTitle: String {
        switch switching {
        case .idle: return "Workspace switch: not requested"
        case .pending: return "Workspace switch: in progress"
        case .sent: return "Workspace switch: request sent"
        case .failed: return "Workspace switch: failed; check target app"
        }
    }
}
