import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing

/// One frame as it travelled on the socket.
private struct ReceivedFrame {
    var kind: UInt8
    var payload: [UInt8]

    /// The JSON object of a control frame, or `nil`.
    var object: [String: Any]? {
        guard kind == 1 else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(payload))) as? [String: Any]
    }

    /// The name of the control message, which is the only key of its object.
    var messageName: String? { object?.keys.first }

    /// The fields of a control message.
    var fields: [String: Any]? { messageName.flatMap { object?[$0] as? [String: Any] } }
}

/// A client that writes bytes to the socket by hand, without the protocol
/// code of the product. The frames are built from numbers written out here, so
/// a client that breaks the rules can be as wrong as a test wants.
private final class HostileClient: Sendable {
    private let descriptor: Int32

    init(socketPath: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        // Set before connecting. Once the other side has closed, the system
        // refuses the option, and a write would end the test with SIGPIPE.
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: socketPath.utf8.prefix($0.count - 1)) }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard descriptor >= 0, result == 0 else {
            let code = errno
            if descriptor >= 0 { close(descriptor) }
            throw HarnessError.commandFailed(description: "connect failed: \(String(cString: strerror(code)))")
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

}
