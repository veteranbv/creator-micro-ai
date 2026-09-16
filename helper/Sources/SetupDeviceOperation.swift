import AppKit
import Foundation

// Uses the same backup/readback configurator as the command-line setup.
// Output is a bounded private protocol, never displayed as vendor diagnostics.
final class SetupDeviceOperation {
    struct Result { let matches: Bool; let backup: URL?; let succeeded: Bool }
    private var process: Process?
    private var deadline: DispatchWorkItem?

    func run(command: String, backup: URL? = nil, completion: @escaping (Result) -> Void) {
        guard process == nil, ["--check", "--apply", "--restore"].contains(command),
              let resources = Bundle.main.resourceURL else {
            completion(Result(matches: false, backup: nil, succeeded: false)); return
        }
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/Applications/input.app/Contents/MacOS/input")
        task.arguments = [resources.appendingPathComponent("device/configure.js").path, "--setup", command]
        if let backup { task.arguments?.append(backup.path) }
        task.environment = ["ELECTRON_RUN_AS_NODE": "1", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        process = task
        do {
            try task.run()
            try? pipe.fileHandleForWriting.close()
        }
        catch {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            process = nil
            completion(Result(matches: false, backup: nil, succeeded: false)); return
        }
        // The configurator has a 30-second deadline. This also covers a wedged vendor load.
        let timeout = DispatchWorkItem { if task.isRunning { kill(task.processIdentifier, SIGKILL) } }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 35, execute: timeout)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var output = Data(), overflow = false
            do {
                while let chunk = try pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                    guard output.count + chunk.count <= 16384 else {
                        overflow = true
                        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                        break
                    }
                    output.append(chunk)
                }
            } catch { overflow = true; if task.isRunning { kill(task.processIdentifier, SIGKILL) } }
            task.waitUntilExit()
            try? pipe.fileHandleForReading.close()
            let result = Self.decode(output, success: !overflow && task.terminationStatus == 0)
            DispatchQueue.main.async {
                self?.deadline?.cancel()
                self?.deadline = nil
                self?.process = nil
                completion(result)
            }
        }
    }

    static func decode(_ data: Data, success: Bool) -> Result {
        var matches = false, completions = 0, valid = true, backup: URL?
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Creator Micro AI/backups").standardizedFileURL.path + "/"
        for line in data.split(separator: 10) {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                valid = false; continue
            }
            if event["type"] as? String == "complete", Set(event.keys) == ["type", "matches"],
               let value = event["matches"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() {
                completions += 1; matches = value.boolValue
            } else if event["type"] as? String == "backup", Set(event.keys) == ["type", "file"],
                      let path = event["file"] as? String, path.hasPrefix("/"), backup == nil, completions == 0 {
                let url = URL(fileURLWithPath: path).standardizedFileURL
                if url.path.hasPrefix(base), url.lastPathComponent == "keymap.before.json" { backup = url }
                else { valid = false }
            } else { valid = false }
        }
        let succeeded = success && valid && completions == 1
        return Result(matches: succeeded && matches, backup: backup, succeeded: succeeded)
    }
}
