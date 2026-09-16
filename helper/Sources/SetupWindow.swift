import AppKit
import ApplicationServices
import CryptoKit

private final class SetupContentStack: NSStackView {
    override var isFlipped: Bool { true }
}

final class SetupWindow: NSWindowController, NSWindowDelegate {
    private let health: () -> HelperHealth
    private let pauseBridge: (@escaping (Bool) -> Void) -> Void
    private let resumeBridge: () -> Void
    private let operation = SetupDeviceOperation()
    private var state = SetupState()
    private let defaults: UserDefaults
    private let build: String
    private let body = SetupContentStack()
    private let sidebar = NSStackView()
    private let heading = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let next = NSButton(title: "Continue", target: nil, action: nil)
    private let back = NSButton(title: "Back", target: nil, action: nil)
    private let live = NSTextField(wrappingLabelWithString: "")
    private var labels: [String: NSTextField] = [:]
    private var checks: [String: NSButton] = [:]
    private var operationButtons: [NSButton] = []
    private var message = "Connect by USB for profile checks and changes. Bluetooth operation is tested later."
    private var recovery: URL?

    init(health: @escaping () -> HelperHealth,
         pauseBridge: @escaping (@escaping (Bool) -> Void) -> Void,
         resumeBridge: @escaping () -> Void, defaults: UserDefaults = .standard) {
        self.health = health
        self.pauseBridge = pauseBridge
        self.resumeBridge = resumeBridge
        self.defaults = defaults
        if let executable = Bundle.main.executableURL, let bytes = try? Data(contentsOf: executable) {
            build = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        } else { build = UUID().uuidString }
        state.restore(defaults.dictionary(forKey: "setupProgress") ?? [:], build: build)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Creator Micro AI · Setup"
        window.minSize = NSSize(width: 880, height: 700)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        assemble()
        refresh()
        render()
        window.center()
    }

    required init?(coder: NSCoder) { nil }
    var needsFirstRun: Bool { defaults.string(forKey: "setupCompletedBuild") != build }
    var isBusy: Bool { state.busy }

    func present() {
        refresh()
        render()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func save() { defaults.set(state.saved(build: build), forKey: "setupProgress") }

    private func assemble() {
        guard let content = window?.contentView else { return }
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 18
        sidebar.edgeInsets = NSEdgeInsets(top: 32, left: 24, bottom: 24, right: 20)
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.18, alpha: 1).cgColor
        sidebar.addArrangedSubview(text("CREATOR\nMICRO AI", size: 23, weight: .bold, color: .white))
        sidebar.addArrangedSubview(text("One layout.\nFour workspaces.", size: 15, color: .init(white: 0.8, alpha: 1)))
        for step in SetupState.Step.allCases {
            let label = text("\(step.rawValue + 1)   \(step.title)", size: 14, weight: .medium, color: .white)
            label.tag = step.rawValue + 100
            sidebar.addArrangedSubview(label)
        }
        let spacer = NSView()
        sidebar.addArrangedSubview(spacer)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        sidebar.addArrangedSubview(text("Built on Work Louder.\nIndependent. Privacy first.", size: 12, color: .init(white: 0.8, alpha: 1)))
        let main = NSView()
        let layout = NSStackView(views: [sidebar, main])
        layout.orientation = .horizontal
        layout.alignment = .top
        layout.spacing = 0
        content.addSubview(layout)
        layout.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 210).isActive = true
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: content.leadingAnchor), layout.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            layout.topAnchor.constraint(equalTo: content.topAnchor), layout.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            main.widthAnchor.constraint(equalTo: layout.widthAnchor, constant: -210),
            sidebar.heightAnchor.constraint(equalTo: layout.heightAnchor), main.heightAnchor.constraint(equalTo: layout.heightAnchor)
        ])
        heading.font = .systemFont(ofSize: 30, weight: .bold)
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 16
        body.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 20, right: 8)
        scroll.documentView = body
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])
        live.font = .systemFont(ofSize: 12)
        live.textColor = .secondaryLabelColor
        back.target = self; back.action = #selector(previousStep); back.bezelStyle = .rounded
        next.target = self; next.action = #selector(nextStep); next.bezelStyle = .rounded
        next.keyEquivalent = "\r"
        let help = button("Setup help", action: #selector(showHelp))
        let footer = NSStackView(views: [help, NSView(), back, next])
        footer.orientation = .horizontal; footer.spacing = 12
        for view in [heading, subtitle, scroll, live, footer] { main.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: main.topAnchor, constant: 30),
            heading.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 30),
            heading.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -30),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor), subtitle.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: live.topAnchor, constant: -12),
            live.leadingAnchor.constraint(equalTo: heading.leadingAnchor), live.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            live.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: heading.leadingAnchor), footer.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -24)
        ])
    }

    private func text(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.isSelectable = true
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func paragraph(_ value: String) {
        let label = text(value)
        body.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -8).isActive = true
    }

    private func card(_ title: String, detail: String, key: String? = nil) {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.wantsLayer = true; stack.layer?.cornerRadius = 12
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        stack.addArrangedSubview(text(title, size: 16, weight: .semibold))
        let description = text(detail, color: .secondaryLabelColor)
        stack.addArrangedSubview(description)
        if let key { labels[key] = description }
        body.addArrangedSubview(stack)
        stack.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -8).isActive = true
        description.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
    }

    private func checkbox(_ title: String, key: String, checked: Bool) {
        let control = NSButton(checkboxWithTitle: title, target: self, action: #selector(confirmCheck(_:)))
        control.identifier = NSUserInterfaceItemIdentifier(key)
        control.state = checked ? .on : .off
        control.font = .systemFont(ofSize: 13)
        checks[key] = control
        body.addArrangedSubview(control)
    }

    private func render() {
        body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
        labels.removeAll(); checks.removeAll(); operationButtons.removeAll()
        for case let label as NSTextField in sidebar.arrangedSubviews where label.tag >= 100 {
            label.textColor = label.tag == state.step.rawValue + 100 ? .init(calibratedRed: 0.5, green: 0.85, blue: 1, alpha: 1) : .init(white: 0.7, alpha: 1)
            label.setAccessibilityValue(label.tag == state.step.rawValue + 100 ? "Current step" : "")
        }
        let titles = ["Make room for your ideas.", "A quick compatibility check.", "You stay in control.", "Your device. Your choice.", "Talk. Tap. Keep going.", "Make it yours.", "Ready when you are."]
        let descriptions = [
            "A guided setup for Creator Micro 2. No terminal required.",
            "We check the apps this profile actually supports. Nothing is installed silently.",
            "Two separate permissions. We check this running app, not just the settings switches.",
            "Check what is already on your device before choosing to replace anything.",
            "Use the dictation app you prefer with one shared shortcut.",
            "These checks are yours to confirm. We never record your typing or clipboard.",
            "Live checks and your confirmations, clearly separated."
        ]
        heading.stringValue = titles[state.step.rawValue]
        subtitle.stringValue = descriptions[state.step.rawValue]
        switch state.step {
        case .welcome:
            if let icon = NSImage(named: NSImage.applicationIconName) {
                let image = NSImageView(image: icon)
                image.imageScaling = .scaleProportionallyUpOrDown
                image.widthAnchor.constraint(equalToConstant: 92).isActive = true
                image.heightAnchor.constraint(equalToConstant: 92).isActive = true
                image.setAccessibilityLabel("Creator Micro AI app icon")
                body.addArrangedSubview(image)
            }
            card("One layout. Four workspaces.", detail: "1  Codex     2  ChatGPT\n3  Claude Code     4  Claude Chat\n\nKeep the same controls as you move between desktop views.")
            paragraph("This independent, fan-made companion builds on Work Louder’s Creator Micro 2 and Input. It does not replace their app or firmware.")
            card("Private by design", detail: "No keystroke recording. No clipboard reading. No analytics or runtime action log. Your dictation and AI apps have their own privacy policies.")
            paragraph("Close this window whenever you need. Your setup choices stay on this Mac. Reopen Creator Micro AI to pick up where you left off.")
            body.addArrangedSubview(button("Explore the matching controls", action: #selector(openReference)))
        case .apps:
            card("A permanent home for the helper", detail: "Checking…", key: "installation")
            body.addArrangedSubview(button("Show this helper in Finder", action: #selector(revealHelper)))
            card("Work Louder Input", detail: "Checking…", key: "input")
            card("ChatGPT desktop", detail: "Checking…", key: "chatgpt")
            card("Claude desktop", detail: "Checking…", key: "claude")
            paragraph("This profile targets Input 0.18.4, ChatGPT with Chat/Codex views, and Claude with Chat/Code views. Use a US keyboard layout for the @ key. Other app layouts or Input versions need separate verification.")
            body.addArrangedSubview(button("Get Work Louder Input", action: #selector(openInputWebsite)))
            body.addArrangedSubview(button("Open Applications", action: #selector(openApplications)))
        case .permissions:
            card("1. Accessibility", detail: "Checking…", key: "accessibility")
            paragraph("Lets the helper switch supported workspaces and press controls you request. It can transiently read accessibility labels, including message excerpts, but does not save them.")
            body.addArrangedSubview(button("Open Accessibility settings", action: #selector(openAccessibility)))
            card("2. Input Monitoring", detail: "Checking…", key: "monitoring")
            paragraph("The Input-based device bridge needs this separate permission. macOS grants broad input access; this helper does not record typing. Enable the same installed Creator Micro AI app in both lists.")
            body.addArrangedSubview(button("Open Input Monitoring settings", action: #selector(openMonitoring)))
            body.addArrangedSubview(button("Show the app to add to both lists", action: #selector(revealHelper)))
            body.addArrangedSubview(button("Restart helper after permission changes", action: #selector(restart)))
            paragraph("An enabled switch can be stale after an update. If access is still missing, remove and re-add this installed app in BOTH lists, enable both, then restart. macOS may ask for Touch ID or your password. Never enter either in this helper.")
        case .profile:
            card("Device connection", detail: "Checking…", key: "device")
            card("Profile check", detail: message, key: "profile")
            paragraph("Connect exactly one Creator Micro 2 by USB. Profile reads and writes over Bluetooth are not verified. Close Input’s configuration window before continuing.")
            checkbox("USB connected; ready to check this device", key: "usb", checked: false)
            let inspect = button("Check existing profile", action: #selector(checkProfile))
            let apply = button("Back up and apply this profile…", action: #selector(applyProfile))
            let restore = button("Restore a saved profile…", action: #selector(restoreProfile))
            operationButtons = [inspect, apply, restore]
            operationButtons.forEach { body.addArrangedSubview($0) }
            body.addArrangedSubview(button("Show recovery copies", action: #selector(showRecovery)))
            paragraph("Applying replaces all device profiles, macros, lighting and linked-app configuration. We save the previous keymap first and verify the readback. An existing matching profile needs no rewrite. Restart Input after a change to refresh its cached labels.")
        case .dictation:
            card("Control + Shift + D", detail: "One tap starts recording. The next tap stops and inserts into the focused app. Configure this as a global toggle, not hold-to-talk.")
            paragraph("Superwhisper is the maintainer’s choice, not a requirement. Choose any tool that can use this shortcut and insert into both desktop apps without a manual paste.")
            paragraph("In a disposable draft, try three short phrases. Each should appear once. Do not send them. If text repeats, check toggle mode and the single active switch under the wide key.")
            checkbox("Dictation inserts once per tap cycle", key: "dictation", checked: state.dictationConfirmed)
        case .practice:
            card("First: the four-layer cycle", detail: "With USB connected, cycle 1 → 2 → 3 → 4 → 1. Confirm the foreground app AND its Chat/Code view at every step. Color changes alone do not count.")
            checkbox("USB: all four app/view transitions work", key: "wired", checked: state.wiredConfirmed)
            card("Then: your everyday controls", detail: "Use disposable drafts. Check dictation, New chat, Escape, @, Backspace, Undo, ⇧ ↵ and Submit. Test search, model picker, Copy response, all eight joystick directions and the dial.\n\nFor Y/X, use a harmless permission request. Y must choose Allow once; X must deny. With no request, both must leave KEEP THIS DRAFT unchanged.")
            checkbox("I tested the controls across all four layers", key: "controls", checked: state.controlsConfirmed)
            card("Bluetooth, if you use it", detail: "Unplug USB and connect over Bluetooth. Repeat the cycle and controls, then power-cycle the device and repeat after reconnection. Leave unchecked if not tested.")
            checkbox("Bluetooth: switching, controls and reconnection work", key: "bluetooth", checked: state.bluetoothConfirmed)
            paragraph("After any disconnection, return to Your device and recheck the profile over USB before finishing. Your completed test confirmations are kept.")
            body.addArrangedSubview(button("Open the side-by-side control reference", action: #selector(openReference)))
            body.addArrangedSubview(button("Review permissions or connection", action: #selector(reviewPermissions)))
        case .ready:
            card("Live status", detail: "Checking…", key: "summary")
            card("Your confirmations", detail: "USB switching: \(state.wiredConfirmed ? "confirmed" : "not tested")\nControls: \(state.controlsConfirmed ? "confirmed" : "not tested")\nDictation: \(state.dictationConfirmed ? "confirmed" : "not tested")\nBluetooth: \(state.bluetoothConfirmed ? "confirmed" : "not tested")")
            paragraph("Keep Input installed. Actions follow the supported app in front, not the layer. Nothing starts at login unless you choose to add it in macOS Login Items.")
            paragraph("Need help later? Open Creator Micro AI from Applications, or choose Setup & Status from its menu-bar icon. Closing setup leaves the helper running; Quit stops the helper and its bridge.")
            body.addArrangedSubview(button("Open control reference", action: #selector(openReference)))
            body.addArrangedSubview(button("Review permissions or connection", action: #selector(reviewPermissions)))
        }
        refresh()
        window?.contentView?.layoutSubtreeIfNeeded()
        if let scroll = body.enclosingScrollView {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        window?.recalculateKeyViewLoop()
        window?.makeFirstResponder(heading)
    }

    func refresh() {
        let current = health()
        let wasConnected = state.connected
        state.accessibility = current.accessibilityTrusted
        state.inputMonitoring = current.inputMonitoringTrusted
        state.connected = current.connection == .connected
        if wasConnected && !state.connected {
            state.profileMatches = false
            if !state.busy { message = "Device disconnected. Reconnect by USB and check the profile again before finishing." }
        }
        let input = Bundle(url: URL(fileURLWithPath: "/Applications/input.app"))
        let version = input?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let kit = FileManager.default.fileExists(atPath: "/Applications/input.app/Contents/Resources/app.asar")
        let inputReady = version == "0.18.4" && kit
        let chatReady = Bundle(url: URL(fileURLWithPath: "/Applications/ChatGPT.app"))?.bundleIdentifier == "com.openai.codex"
        let claudeReady = Bundle(url: URL(fileURLWithPath: "/Applications/Claude.app"))?.bundleIdentifier == "com.anthropic.claudefordesktop"
        let installed = SetupState.isInstalled(at: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser)
        state.appsReady = installed && inputReady && chatReady && claudeReady
        labels["installation"]?.stringValue = installed ? "✓ Running from Applications" :
            "Move Creator Micro AI.app into Applications, quit this copy, then open the installed app. Do this before granting permissions. Existing installations should be kept as recovery copies, not overwritten while running."
        labels["input"]?.stringValue = inputReady ? "✓ Input 0.18.4 detected" : "Needs attention: install the supported Input 0.18.4 in Applications."
        labels["chatgpt"]?.stringValue = chatReady ? "✓ Supported ChatGPT app detected. Confirm Chat/Codex views during the test." : "Needs attention: supported ChatGPT desktop not found in Applications."
        labels["claude"]?.stringValue = claudeReady ? "✓ Claude detected. Confirm Chat/Code views during the test." : "Needs attention: Claude desktop not found in Applications."
        labels["accessibility"]?.stringValue = current.accessibilityTitle
        labels["monitoring"]?.stringValue = current.inputMonitoringTitle
        labels["device"]?.stringValue = state.busy ? "Bridge paused while checking the profile." : current.connectionTitle
        labels["profile"]?.stringValue = message
        labels["summary"]?.stringValue = "Apps: \(state.appsReady ? "compatible installation detected" : "needs attention")\n\(current.accessibilityTitle)\n\(current.inputMonitoringTitle)\n\(current.connectionTitle)\nProfile: \(state.profileMatches ? "verified this session" : "check required")"
        live.stringValue = state.busy ? "Device operation in progress. Keep USB connected." : "\(current.connectionTitle) · \(current.switchingTitle)"
        next.title = state.step == .ready ? "Finish setup" : "Continue"
        next.isEnabled = state.canContinue
        back.isEnabled = state.step != .welcome && !isBusy
        operationButtons.forEach { $0.isEnabled = !isBusy && state.appsReady && state.permissionsReady && checks["usb"]?.state == .on }
        checks.values.forEach { $0.isEnabled = !isBusy }
    }

    @objc private func nextStep() {
        refresh()
        guard state.canContinue else { return }
        if state.step == .ready {
            defaults.set(build, forKey: "setupCompletedBuild")
            save(); close(); return
        }
        state.step = SetupState.Step(rawValue: state.step.rawValue + 1) ?? .ready
        save(); render()
    }
    @objc private func previousStep() {
        guard !isBusy else { return }
        state.step = SetupState.Step(rawValue: state.step.rawValue - 1) ?? .welcome
        save(); render()
    }
    @objc private func reviewPermissions() { guard !isBusy else { return }; state.step = .permissions; save(); render() }
    @objc private func confirmCheck(_ sender: NSButton) {
        let checked = sender.state == .on
        switch sender.identifier?.rawValue {
        case "dictation": state.dictationConfirmed = checked
        case "wired": state.wiredConfirmed = checked
        case "controls": state.controlsConfirmed = checked
        case "bluetooth": state.bluetoothConfirmed = checked
        default: break
        }
        save(); refresh()
    }
    @objc private func openReference() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("reference/layout.html") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func openInputWebsite() { NSWorkspace.shared.open(URL(string: "https://worklouder.cc")!) }
    @objc private func openApplications() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
    @objc private func revealHelper() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc private func openAccessibility() {
        guard !isBusy else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openMonitoring() {
        guard !isBusy else { return }
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc private func restart() {
        guard !isBusy else { return }
        save(); state.busy = true; refresh()
        pauseBridge { [weak self] stopped in
            guard let self else { return }
            guard stopped else {
                self.state.busy = false; self.resumeBridge(); self.refresh()
                self.alert("Could not restart", "The device bridge did not stop. Quit and reopen the helper before trying again.")
                return
            }
            // Wait for this process to exit before reopening, so its exclusive
            // hotkeys are released. Give shutdown up to 20 seconds. Positional
            // arguments keep paths out of shell code.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "attempt=0; while /bin/kill -0 \"$1\" 2>/dev/null; do attempt=$((attempt + 1)); [ \"$attempt\" -lt 200 ] || exit 1; /bin/sleep 0.1; done; /usr/bin/open -n \"$2\" --args --setup", "relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
            relaunch.environment = [:]
            relaunch.standardInput = FileHandle.nullDevice
            relaunch.standardOutput = FileHandle.nullDevice
            relaunch.standardError = FileHandle.nullDevice
            do {
                try relaunch.run()
                self.state.busy = false
                NSApp.terminate(nil)
            } catch {
                self.state.busy = false; self.resumeBridge(); self.refresh()
                self.alert("Could not restart", "Quit Creator Micro AI, then reopen the installed app from Applications.")
            }
        }
    }
    @objc private func showHelp() {
        alert("Let’s get you unstuck", "If the switches are on but nothing happens, remove and re-add the installed Creator Micro AI in BOTH Accessibility and Input Monitoring, enable both, then restart.\n\nIf the bridge is unavailable, check Input 0.18.4 and reconnect the device. Do not rewrite a working profile just because an app did not switch.\n\nYour setup choices are saved locally. Reopen this app to continue.")
    }
    private func alert(_ title: String, _ detail: String) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    @objc private func showRecovery() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Creator Micro AI/backups")
        if let recovery { NSWorkspace.shared.activateFileViewerSelecting([recovery]) }
        else if FileManager.default.fileExists(atPath: directory.path) { NSWorkspace.shared.open(directory) }
        else { alert("No recovery copy yet", "A private recovery copy is created before the first profile write. Checking the profile does not change the device or create a backup.") }
    }
    @objc private func checkProfile() { runProfile("--check") }
    @objc private func applyProfile() {
        guard !isBusy, let window else { return }
        let confirmation = NSAlert()
        confirmation.messageText = "Replace this device’s configuration?"
        confirmation.informativeText = "This replaces ALL profiles, macros, lighting and linked-app configuration with the four-layer setup. Your current keymap is backed up before writing. Keep exactly one device connected by USB."
        confirmation.addButton(withTitle: "Cancel")
        confirmation.addButton(withTitle: "Back up and replace")
        confirmation.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.runProfile("--apply") }
        }
    }
    @objc private func restoreProfile() {
        guard !isBusy, let window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Choose a saved keymap to restore"
        panel.prompt = "Choose backup"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let confirmation = NSAlert()
            confirmation.messageText = "Restore this saved configuration?"
            confirmation.informativeText = "This replaces the device’s current configuration with the selected file. A copy of the current keymap is saved if it can be read. Keep USB connected."
            confirmation.addButton(withTitle: "Cancel"); confirmation.addButton(withTitle: "Restore")
            confirmation.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn { self.runProfile("--restore", backup: url) }
            }
        }
    }
    private func runProfile(_ command: String, backup: URL? = nil) {
        refresh()
        guard !isBusy, state.appsReady, state.permissionsReady, checks["usb"]?.state == .on else { return }
        state.busy = true; state.profileMatches = false
        if command != "--check" { state.invalidatePhysicalChecks(); save() }
        message = "Pausing the bridge before accessing the device…"; refresh()
        pauseBridge { [weak self] stopped in
            guard let self else { return }
            guard stopped else {
                self.state.busy = false
                self.message = "The bridge did not stop. No profile operation started. Quit and reopen the helper, then retry."
                self.resumeBridge(); self.refresh(); return
            }
            self.state.connected = false
            self.operation.run(command: command, backup: backup) { [weak self] result in
                guard let self else { return }
                self.recovery = result.backup ?? self.recovery
                self.state.busy = false
                self.state.profileMatches = result.matches
                if result.succeeded {
                    if command == "--restore" {
                        self.message = "Saved configuration restored and readback verified. Check the profile before continuing."
                    } else {
                        self.message = result.matches ? "✓ The device readback matches this four-layer profile. Waiting for the bridge to reconnect if needed." :
                            "The keymap can be read, but it is not this profile. Keep it as-is or deliberately choose to back up and apply."
                    }
                } else {
                    self.message = command == "--check" ? "Check failed. No profile write was requested. Check USB, permissions and Input, then retry." :
                        "The operation failed or timed out. A write may be incomplete. Keep the recovery copy and use Restore before relying on this device."
                }
                self.resumeBridge(); self.refresh()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isBusy { NSSound.beep(); return false }
        save(); return true
    }
}
