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
            let data = BridgePipeReader.readAvailable(from: handle)
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
        precondition(BridgePipeReader.readAvailable(from: bounded.fileHandleForReading).count == 8192)
        precondition(BridgePipeReader.readAvailable(from: bounded.fileHandleForReading).count == 808)
        try bounded.fileHandleForWriting.close()
        precondition(BridgePipeReader.readAvailable(from: bounded.fileHandleForReading).isEmpty)
        try bounded.fileHandleForReading.close()
        print("PASS: short live-pipe chunks, repeated reads, bounded reads and EOF. No device access.")
    }
}
