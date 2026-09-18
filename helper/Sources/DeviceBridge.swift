import AppKit
import Foundation

enum WorkspaceMode: String, CaseIterable {
    case codex
    case chatgpt
    case claudeCode = "claude-code"
    case claude

    var processToken: String {
        switch self {
        case .codex: return "cc.worklouder.ai.codex"
        case .claudeCode: return "cc.worklouder.ai.claude-code"
        case .claude: return "cc.worklouder.ai.claude"
        case .chatgpt: return "cc.worklouder.ai.chatgpt"
        }
    }

    var layer: Int {
        switch self {
        case .codex: return 1
        case .chatgpt: return 2
        case .claudeCode: return 3
        case .claude: return 4
        }
    }

    var appURL: URL {
        switch self {
        case .codex, .chatgpt: return URL(fileURLWithPath: "/Applications/ChatGPT.app")
        case .claudeCode, .claude: return URL(fileURLWithPath: "/Applications/Claude.app")
        }
    }

    static func from(layer: Int) -> WorkspaceMode? {
        allCases.first(where: { $0.layer == layer })
    }
}

struct BridgeMessage: Decodable {
    let type: String
    let layer: Int?
    let requestId: Int?
}

// Private inherited pipes, not a socket accessible to unrelated local processes.
final class DeviceBridge {
    var onMessage: ((BridgeMessage) -> Void)?
    var onFailure: ((HelperHealth.BridgeFailure) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var requestID = 0
    private var stopped = false
    private var nextStart: TimeInterval = 0
    private var failures = 0
    private var readyAt: TimeInterval?
    private let makeProcess: () -> Process?
    private let uptime: () -> TimeInterval

    init(makeProcess: @escaping () -> Process? = DeviceBridge.makeVendorProcess,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.makeProcess = makeProcess
        self.uptime = now
    }

    static func makeVendorProcess() -> Process? {
        guard let script = Bundle.main.path(forResource: "worklouder_device_bridge", ofType: "js") else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/Applications/input.app/Contents/MacOS/input")
        task.arguments = [script]
        // Do not pass API keys or other shell environment values into the USB child.
        task.environment = ["ELECTRON_RUN_AS_NODE": "1", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        return task
    }

    func start() {
        guard !stopped, process == nil, uptime() >= nextStart else { return }
        guard let task = makeProcess() else {
            failed(.launchFailed)
            return
        }
        let incoming = Pipe(), outgoing = Pipe()
        task.standardInput = incoming
        task.standardOutput = outgoing
        task.standardError = FileHandle.nullDevice
        process = task
        input = incoming.fileHandleForWriting
        output = outgoing.fileHandleForReading
        buffer.removeAll()
        outgoing.fileHandleForReading.readabilityHandler = { [weak self, weak task] handle in
            let data = BridgePipe.readAvailable(from: handle)
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                guard let self, let task, self.process === task else { return }
                if !data.isEmpty { self.consume(data) }
            }
        }
        task.terminationHandler = { [weak self, weak task] _ in
            DispatchQueue.main.async {
                guard let self, let task, self.process === task else { return }
                self.closeHandles()
                self.process = nil
                if !self.stopped {
                    self.failed(task.terminationReason == .uncaughtSignal ? .crashed : .exited)
                }
            }
        }
        do {
            try BridgePipe.prepareWriter(incoming.fileHandleForWriting.fileDescriptor)
            try task.run()
            // Only the child may hold these ends; otherwise EOF/EPIPE is hidden.
            // Foundation may already have closed them while launching the child.
            try? incoming.fileHandleForReading.close()
            try? outgoing.fileHandleForWriting.close()
        }
        catch {
            if task.isRunning { task.terminate() }
            closeHandles()
            process = nil
            failed(.launchFailed)
        }
    }

    private func failed(_ reason: HelperHealth.BridgeFailure) {
        // A ready message alone must not reset a rapidly crashing child.
        // Thirty healthy seconds resets the 3, 6, 12, 24, 30-second retry sequence.
        if let readyAt, uptime() - readyAt >= 30 { failures = 0 }
        readyAt = nil
        let delay = min(30.0, 3.0 * pow(2.0, Double(failures)))
        failures = min(failures + 1, 4)
        nextStart = uptime() + delay
        onMessage?(BridgeMessage(type: "error", layer: nil, requestId: nil))
        onFailure?(reason)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    func focus(_ mode: WorkspaceMode) -> Int? {
        guard process?.isRunning == true, let input else { return nil }
        requestID += 1
        let payload: [String: Any] = ["type": "focus", "token": mode.processToken, "requestId": requestID]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)
        do { try input.write(contentsOf: data); return requestID }
        catch { process?.terminate(); return nil }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            guard line.count <= 4096 else { process?.terminate(); return }
            buffer.removeSubrange(...newline)
            guard let message = try? JSONDecoder().decode(BridgeMessage.self, from: line),
                  ["ready", "layer", "applied", "error"].contains(message.type),
                  message.layer == nil || (1...4).contains(message.layer!) else { continue }
            if message.type == "ready", message.layer != nil, readyAt == nil { readyAt = uptime() }
            onMessage?(message)
        }
        if buffer.count > 4096 { buffer.removeAll(); process?.terminate() }
    }

    private func closeHandles() {
        output?.readabilityHandler = nil
        try? output?.close()
        try? input?.close()
        output = nil
        input = nil
        buffer.removeAll()
    }

    func stop() {
        stopped = true
        if let readyAt, uptime() - readyAt >= 30 { failures = 0 }
        readyAt = nil
        closeHandles()
        process?.terminate()
    }

    func pauseForSetup(completion: @escaping (Bool) -> Void) {
        stop()
        onMessage?(BridgeMessage(type: "error", layer: nil, requestId: nil))
        let deadline = Date().addingTimeInterval(4)
        func check() {
            if process?.isRunning != true {
                closeHandles()
                process = nil
                completion(true)
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
            }
        }
        check()
    }

    func resumeAfterSetup() { stopped = false; start() }
}

final class HelperLifecycle: NSObject, NSApplicationDelegate {
    private let bridge: DeviceBridge
    private let healthSnapshot: () -> HelperHealth
    private var statusItem: NSStatusItem?
    private lazy var setup = SetupWindow(health: healthSnapshot,
        pauseBridge: { [weak self] completion in
            guard let self else { completion(false); return }
            self.bridge.pauseForSetup(completion: completion)
        }, resumeBridge: { [weak self] in self?.bridge.resumeAfterSetup() })
    private let connectionInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessibilityInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let inputMonitoringInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let switchingInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let recoveryInfo = NSMenuItem(title: "Check device connection, Input installation and Input Monitoring.", action: nil, keyEquivalent: "")
    private let permissionInfo = NSMenuItem(title: "After updating, re-add this app in both permission lists, then quit and reopen.", action: nil, keyEquivalent: "")
    init(bridge: DeviceBridge, health: @escaping () -> HelperHealth) {
        self.bridge = bridge
        self.healthSnapshot = health
    }
    func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Creator Micro AI")
        let menu = NSMenu()
        let info = NSMenuItem(title: "Creator Micro AI · local helper", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        let setupItem = NSMenuItem(title: "Setup & Status…", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        menu.addItem(.separator())
        for row in [connectionInfo, accessibilityInfo, inputMonitoringInfo, switchingInfo, recoveryInfo, permissionInfo] {
            row.isEnabled = false
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Creator Micro AI", action: #selector(quitHelper), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        updateStatus()
    }
    func updateStatus() {
        setup.refresh()
        let current = healthSnapshot()
        connectionInfo.title = current.connectionTitle
        accessibilityInfo.title = current.accessibilityTitle
        inputMonitoringInfo.title = current.inputMonitoringTitle
        switchingInfo.title = current.switchingTitle
        recoveryInfo.isHidden = current.connection != .unavailable
        permissionInfo.isHidden = current.accessibilityTrusted && current.inputMonitoringTrusted
        let description = "Creator Micro AI. \(current.connectionTitle). \(current.accessibilityTitle). \(current.inputMonitoringTitle). \(current.switchingTitle)."
        statusItem?.button?.image = NSImage(systemSymbolName: current.needsAttention ? "exclamationmark.triangle" : "keyboard",
                                          accessibilityDescription: description)
        statusItem?.button?.toolTip = description
    }
    @objc private func openSetup() { setup.present() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if setup.needsFirstRun || CommandLine.arguments.contains("--setup") { setup.present() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setup.present()
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if setup.isBusy { NSSound.beep(); setup.present(); return .terminateCancel }
        return .terminateNow
    }
    @objc private func quitHelper() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { bridge.stop() }
}
