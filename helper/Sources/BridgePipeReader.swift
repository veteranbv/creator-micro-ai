import Darwin
import Foundation

enum BridgePipeReader {
    // A pipe message can be much smaller than the buffer while its writer stays open.
    // One read returns those bytes immediately; message framing belongs to DeviceBridge.
    static func readAvailable(from handle: FileHandle) -> Data {
        var bytes = [UInt8](repeating: 0, count: 8192)
        var count: Int
        repeat {
            count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
        } while count < 0 && errno == EINTR
        guard count > 0 else { return Data() }
        return Data(bytes.prefix(count))
    }
}
