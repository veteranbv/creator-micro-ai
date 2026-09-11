import AppKit
import Foundation

// Private inherited pipes, not a socket accessible to unrelated local processes.
final class DeviceBridge {
    var onMessage: ((BridgeMessage) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var requestID = 0
    private var stopped = false

    func start() {
        guard !stopped, process == nil,
              let script = Bundle.main.path(forResource: "worklouder_device_bridge", ofType: "js") else { return }
        let task = Process(), incoming = Pipe(), outgoing = Pipe()
        task.executableURL = URL(fileURLWithPath: "/Applications/input.app/Contents/MacOS/input")
        task.arguments = [script]
        // Do not pass API keys or other shell environment values into the USB child.
        task.environment = ["ELECTRON_RUN_AS_NODE": "1", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        task.standardInput = incoming
        task.standardOutput = outgoing
        task.standardError = FileHandle.nullDevice
        process = task
        input = incoming.fileHandleForWriting
        output = outgoing.fileHandleForReading
        buffer.removeAll()
        outgoing.fileHandleForReading.readabilityHandler = { [weak self, weak task] handle in
            let data = (try? handle.read(upToCount: 8192)) ?? Data()
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
                self.onMessage?(BridgeMessage(type: "error", layer: nil, requestId: nil))
                self.retry()
            }
        }
        do { try task.run() }
        catch {
            closeHandles()
            process = nil
            retry()
        }
    }

    private func retry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
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
        closeHandles()
        process?.terminate()
    }
}

final class HelperLifecycle: NSObject, NSApplicationDelegate {
    private let bridge: DeviceBridge
    private var statusItem: NSStatusItem?
    init(bridge: DeviceBridge) { self.bridge = bridge }
    func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Creator Micro AI")
        let menu = NSMenu()
        let info = NSMenuItem(title: "Creator Micro AI · local helper", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Creator Micro AI", action: #selector(quitHelper), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }
    @objc private func quitHelper() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { bridge.stop() }
}
