import AppKit
import CryptoKit

// Optional visual fixture. No bridge, hotkeys or device operation can start.
// Compile with SetupWindow, SetupState, SetupDeviceOperation and HelperHealth.
@main
enum SetupWindowPreview {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }

    static func preferences(_ suite: String) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suite) else {
            print("FAIL: isolated fixture preferences could not be created"); exit(1)
        }
        return defaults
    }

    static func executableFingerprint() -> String {
        guard let url = Bundle.main.executableURL, let bytes = try? Data(contentsOf: url) else {
            print("FAIL: fixture executable could not be read"); exit(1)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func main() {
        if CommandLine.arguments.dropFirst().first == "--lifecycle" { checkLifecycle(); return }
        let render = CommandLine.arguments.dropFirst().first == "--render"
        if render { renderScreens(); return }
        guard let step = Int(CommandLine.arguments.dropFirst().first ?? "0"), (0...6).contains(step) else { return }
        let suite = "community.creatormicroai.setup-fixture-preferences"
        let defaults = preferences(suite)
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let build = executableFingerprint()
        defaults.set(["step": step, "build": build], forKey: "setupProgress")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = SetupWindow(health: { HelperHealth() },
                                     pauseBridge: { $0(false) }, resumeBridge: {}, defaults: defaults)
        controller.window?.title = "Setup visual fixture · no device access"
        controller.present()
        // Bound an unattended visual session. This is not a hardware test.
        Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { _ in app.stop(nil) }
        app.run()
        controller.close()
    }

    static func checkLifecycle() {
        let app = NSApplication.shared
        require(app.setActivationPolicy(.accessory), "Fixture must start as an accessory app")
        let suite = "community.creatormicroai.setup-fixture-preferences"
        let defaults = preferences(suite)
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SetupWindow(health: { HelperHealth() },
                                     pauseBridge: { $0(false) }, resumeBridge: {}, defaults: defaults)
        controller.window?.title = "Setup lifecycle fixture · no device access"
        for _ in 0..<2 {
            controller.present()
            require(app.activationPolicy() == .accessory, "Opening setup must preserve accessory activation policy")
            require(controller.window?.isVisible == true, "Accessory setup window must be visible")
            controller.present()
            require(app.activationPolicy() == .accessory, "Presenting open setup must preserve accessory activation policy")
            controller.close()
            require(controller.window?.isVisible == false, "Setup window must close")
            require(app.activationPolicy() == .accessory, "Closing setup must preserve accessory activation policy")
        }
        print("Setup open, close and reopen preserve accessory activation policy. No device access.")
    }

    // Render only this fixture's view, not the screen or other apps.
    static func renderScreens() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let suite = "community.creatormicroai.setup-fixture-preferences"
        let defaults = preferences(suite)
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let build = executableFingerprint()
        let directory = URL(fileURLWithPath: "build/setup-preview/renders", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { print("FAIL: fixture output directory could not be created"); exit(1) }
        for step in 0...6 {
            defaults.set(["step": step, "build": build], forKey: "setupProgress")
            let controller = SetupWindow(health: { HelperHealth() },
                                         pauseBridge: { $0(false) }, resumeBridge: {}, defaults: defaults)
            guard let view = controller.window?.contentView else {
                print("FAIL: setup content view is missing"); exit(1)
            }
            // The cached content view excludes the window's normal background.
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            view.layoutSubtreeIfNeeded()
            func checkLayout(_ node: NSView) {
                require(!node.hasAmbiguousLayout, "Ambiguous setup layout: \(type(of: node))")
                if let scroll = node as? NSScrollView {
                    require(scroll.frame.width > 600, "The content column must fill the available window")
                    require(scroll.contentView.bounds.origin.y == 0, "Each step starts at the top")
                    if let document = scroll.documentView, document.frame.height > scroll.contentView.bounds.height + 20 {
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: 20))
                        scroll.layoutSubtreeIfNeeded()
                        require(scroll.contentView.bounds.origin.y == 20, "Long steps remain scrollable")
                        scroll.contentView.scroll(to: .zero)
                    }
                }
                node.subviews.forEach(checkLayout)
            }
            checkLayout(view)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                print("FAIL: setup render buffer could not be created"); exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                print("FAIL: setup render could not be encoded"); exit(1)
            }
            do { try png.write(to: directory.appendingPathComponent("step-\(step).png")) }
            catch { print("FAIL: setup render could not be saved"); exit(1) }
            require(view.bounds.width >= 880 && view.bounds.height >= 600, "Setup window must fit its minimum layout")
            print("Rendered setup screen \(step). No bridge, hotkeys or device access.")
            controller.close()
        }
    }
}
