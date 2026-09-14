import Foundation
import Dispatch

@main
enum BridgePipeTests {
    static func main() throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let writer = pipe.fileHandleForWriting
        let delivered = DispatchSemaphore(value: 0)
        let ended = DispatchSemaphore(value: 0)
        let chunks = [
            Data("{\"type\":\"ready\",\"layer\":1}\n".utf8),
            Data("{\"type\":\"layer\",".utf8),
            Data("\"layer\":3}\n{\"type\":\"layer\",\"layer\":4}\n".utf8)
        ]
        // The writer waits for each read before sending the next chunk. No sleep
        // or buffer-sized payload can hide a reader that waits for more bytes.
        var index = 0
        reader.readabilityHandler = { handle in
            let data = BridgePipe.readAvailable(from: handle)
            if data.isEmpty {
                handle.readabilityHandler = nil
                ended.signal()
                return
            }
            precondition(index < chunks.count && data == chunks[index])
            index += 1
            delivered.signal()
        }
        for chunk in chunks {
            try writer.write(contentsOf: chunk)
            precondition(delivered.wait(timeout: .now() + 5) == .success,
                         "A short bridge chunk must arrive before the writer closes")
        }
        try writer.close()
        precondition(ended.wait(timeout: .now() + 5) == .success)
        try reader.close()

        let bounded = Pipe()
        try bounded.fileHandleForWriting.write(contentsOf: Data(repeating: 0x61, count: 9000))
        precondition(BridgePipe.readAvailable(from: bounded.fileHandleForReading).count == 8192)
        precondition(BridgePipe.readAvailable(from: bounded.fileHandleForReading).count == 808)
        try bounded.fileHandleForWriting.close()
        precondition(BridgePipe.readAvailable(from: bounded.fileHandleForReading).isEmpty)
        try bounded.fileHandleForReading.close()
        let broken = Pipe()
        try BridgePipe.prepareWriter(broken.fileHandleForWriting.fileDescriptor)
        try broken.fileHandleForReading.close()
        var failed = false
        do { try broken.fileHandleForWriting.write(contentsOf: Data([0x0A])) }
        catch { failed = true }
        precondition(failed, "A closed reader must throw without terminating the helper")
        try broken.fileHandleForWriting.close()
        do {
            try BridgePipe.prepareWriter(-1)
            preconditionFailure("Closed descriptors must reject writer setup")
        } catch {}
        let task = Process(), childInput = Pipe(), childOutput = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        task.standardInput = childInput
        task.standardOutput = childOutput
        try BridgePipe.prepareWriter(childInput.fileHandleForWriting.fileDescriptor)
        try task.run()
        try? childInput.fileHandleForReading.close()
        try? childOutput.fileHandleForWriting.close()
        task.waitUntilExit()
        precondition(BridgePipe.readAvailable(from: childOutput.fileHandleForReading).isEmpty)
        failed = false
        do { try childInput.fileHandleForWriting.write(contentsOf: Data([0x0A])) }
        catch { failed = true }
        precondition(failed, "An exited child must not leave a parent-held reader hiding EPIPE")
        try childInput.fileHandleForWriting.close()
        try childOutput.fileHandleForReading.close()
        print("PASS: short live-pipe chunks, bounded reads, EOF and broken-pipe survival. No device access.")
    }
}
