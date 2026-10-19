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

    /// A frame from its parts: four bytes of length, which counts the kind
    /// and the payload, then the kind, then the payload.
    static func frame(kind: UInt8, payload: [UInt8]) -> [UInt8] {
        let length = UInt32(payload.count + 1)
        return [UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF), kind] + payload
    }

    /// A control frame from the text of its message.
    static func control(_ text: String) -> [UInt8] {
        frame(kind: 1, payload: Array(text.utf8))
    }

    static let hello = control(#"{"hello":{"protocolVersion":1}}"#)

    /// Writes the bytes. Returns whether they all went out.
    @discardableResult
    func send(_ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let count = bytes[offset...].withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                offset += count
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// Reads up to `count` bytes, or fewer when the connection ends or the
    /// time passes. `closed` says whether the end came from the other side.
    private func read(count: Int, deadline: ContinuousClock.Instant) -> (bytes: [UInt8], closed: Bool) {
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while bytes.count < count {
            let remaining = deadline - .now
            guard remaining > .zero else { return (bytes, false) }
            var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(clamping: remaining.components.seconds * 1000 + remaining.components.attoseconds / 1_000_000_000_000_000)
            let ready = poll(&entry, 1, max(1, milliseconds))
            if ready < 0 && errno == EINTR { continue }
            if ready <= 0 { continue }
            let received = Darwin.read(descriptor, &buffer, min(buffer.count, count - bytes.count))
            if received > 0 {
                bytes += buffer[..<received]
            } else if received == 0 || (errno != EINTR && errno != EAGAIN) {
                return (bytes, true)
            }
        }
        return (bytes, false)
    }

    /// The next whole frame. `nil` when the other side closed the connection
    /// or the time passed first.
    func receiveFrame(within limit: Duration = .seconds(15)) -> ReceivedFrame? {
        let deadline = ContinuousClock.now + limit
        let field = read(count: 4, deadline: deadline)
        guard field.bytes.count == 4 else { return nil }
        let length = field.bytes.reduce(0) { $0 << 8 | Int($1) }
        guard length >= 1, length <= 64 * 1024 * 1024 + 1 else { return nil }
        let body = read(count: length, deadline: deadline)
        guard body.bytes.count == length else { return nil }
        return ReceivedFrame(kind: body.bytes[0], payload: Array(body.bytes.dropFirst()))
    }

    /// Reads and drops everything until the other side closes the connection.
    /// Returns whether it closed before the time passed.
    func waitForClose(within limit: Duration = .seconds(15)) -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            let result = read(count: 64 * 1024, deadline: deadline)
            if result.closed { return true }
        }
        return false
    }

    /// Says hello and checks the answer.
    func greet() throws {
        send(Self.hello)
        let answer = receiveFrame()
        guard answer?.messageName == "hello" else {
            throw HarnessError.commandFailed(description: "The answer to hello was \(String(describing: answer?.messageName)).")
        }
    }
}
