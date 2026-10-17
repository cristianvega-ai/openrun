import Darwin
import Foundation
import Synchronization

/// A Unix socket that carries frames, for either side of the conversation.
///
/// Sending and receiving block. One thread may send while another receives.
/// Calls to `send` from several threads are safe: each frame goes out whole.
/// Only one thread may call `receive` at a time.
public final class MessageConnection: Sendable {
    /// How long `receive` may wait for the bytes of a frame.
    public enum TimeLimit: Sendable, Equatable {
        /// Waits as long as it takes.
        case unlimited
        /// The whole frame must have arrived by this moment.
        case wholeFrame(by: ContinuousClock.Instant)
        /// Waits as long as it takes for a frame to start. Once it has
        /// started, each part of it must follow within this time.
        case stall(Duration)
    }

    /// A frame body is read in parts of this size, so the memory for a frame
    /// grows only as its bytes arrive.
    private static let readChunkSize = 64 * 1024

    /// The socket, or -1 once `close` has run. A call after `close` then
    /// fails with EBADF instead of using a number that the system may have
    /// given to another file.
    private let descriptorStorage: Atomic<Int32>
    private var descriptor: Int32 { descriptorStorage.load(ordering: .acquiring) }
    /// Held for each frame, so frames go out whole. It also holds the send
    /// timeout of the socket. Nil means none: a send waits as long as it takes.
    private let sendLock = Mutex<Duration?>(nil)

    /// Takes ownership of a connected socket descriptor.
    public init(descriptor: Int32) {
        descriptorStorage = Atomic(descriptor)
        // A write to a socket that the peer closed must return an error. The
        // default is a SIGPIPE that would end the whole process. The system
        // refuses this option once the peer has closed, so `send` also passes
        // MSG_NOSIGNAL.
        Self.turnOffBrokenPipeSignal(on: descriptor)
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }

    deinit {
        close()
    }

    /// Closes the descriptor now, instead of when the last reference goes
    /// away. Call it only once no thread uses the connection any more. The
    /// session process calls it to know when a client's socket is gone, so
    /// that its limit of clients also bounds its descriptors.
    public func close() {
        let closing = descriptorStorage.exchange(-1, ordering: .acquiringAndReleasing)
        if closing >= 0 { Darwin.close(closing) }
    }

    /// Connects to a session process.
    ///
    /// Refuses a folder that other users can change, and a program at the
    /// other end that runs as another user, before a single byte goes out. A
    /// client sends its environment, folder and typed text, which belong to
    /// no one else. See `SocketLocation.checkFolder` and `requirePeer`.
    public static func connect(to location: SocketLocation) throws -> MessageConnection {
        try connect(to: location, expectedPeer: .currentUser)
    }

    /// `connect(to:)` with the user that the peer must run as. Tests pass
    /// another user, because they cannot start a program as one.
    static func connect(to location: SocketLocation, expectedPeer: PeerIdentity) throws -> MessageConnection {
        try location.checkFolder()
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SessionProtocolError.failure(of: "socket") }
        // Before connecting, while the system still accepts the option.
        turnOffBrokenPipeSignal(on: descriptor)
        let result = location.withAddress { Darwin.connect(descriptor, $0, $1) }
        guard result == 0 else {
            let failure = SessionProtocolError.failure(of: "connect")
            Darwin.close(descriptor)
            throw failure
        }
        let connection = MessageConnection(descriptor: descriptor)
        try connection.requirePeer(expectedPeer)
        return connection
    }

    /// Two connected ends, for tests.
    public static func makePair() throws -> (MessageConnection, MessageConnection) {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw SessionProtocolError.failure(of: "socketpair")
        }
        return (MessageConnection(descriptor: descriptors[0]), MessageConnection(descriptor: descriptors[1]))
    }

    /// Writes one whole frame.
    ///
    /// - Parameter stallLimit: When it is set, the write ends with
    ///   `SessionProtocolError.timedOut` once the other side has taken no
    ///   byte for this long. Without it, the write waits as long as it takes.
    public func send(_ message: some FramedMessage, stallLimit: Duration? = nil) throws {
        let bytes = try message.frame().encoded()
        try sendLock.withLock { sendTimeout in
            // MSG_DONTWAIT does not keep a send on a Unix socket of macOS from
            // blocking. A send timeout does: a send that takes no byte for this
            // long returns what it sent, or EAGAIN.
            if sendTimeout != stallLimit {
                Self.setSendTimeout(stallLimit, on: descriptor)
                sendTimeout = stallLimit
            }
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let started = ContinuousClock.now
                    let count = Darwin.send(descriptor, buffer.baseAddress! + offset, buffer.count - offset, MSG_NOSIGNAL)
                    let code = errno
                    if count > 0 {
                        offset += count
                    } else if count < 0 && code == EINTR {
                        continue
                    } else if !(count < 0 && code == EAGAIN && stallLimit != nil) {
                        throw SessionProtocolError.systemCallFailed(function: "write", code: code)
                    }
                    // A send with a timeout returns before the end only when a
                    // wait for room took the whole limit without a byte, or
                    // when a signal came. The time it took tells them apart.
                    if offset < buffer.count, let stallLimit, ContinuousClock.now - started >= stallLimit {
                        throw SessionProtocolError.timedOut(waitingFor: "the other side to take a frame")
                    }
                }
            }
        }
    }

    /// Reads one whole frame and decodes it. Returns `nil` when the peer
    /// closed the connection between two frames.
    ///
    /// Pass `MessageFrame.self` to get the frame without decoding it, so the
    /// caller can tell a frame that it cannot decode from a broken connection.
    ///
    /// - Parameters:
    ///   - timeLimit: How long the bytes of the frame may take.
    ///   - admittingFrame: Called with the size of the frame, its length field
    ///     included, and its kind. It runs after the length field and the kind
    ///     byte, before the payload is read. It may wait for room, or throw to
    ///     stop.
    public func receive<Message: FramedMessage>(
        _ type: Message.Type = Message.self,
        timeLimit: TimeLimit = .unlimited,
        admittingFrame: (_ byteCount: Int, _ kind: MessageFrame.Kind) throws -> Void = { _, _ in }
    ) throws -> Message? {
        guard let field = try read(MessageFrame.lengthFieldSize, startsFrame: true, timeLimit: timeLimit) else {
            return nil
        }
        let length = try MessageFrame.bodyLength(fromLengthField: field)
        // The kind is one byte, read before the payload. The receiver can then
        // give a small control frame, such as detach, room that input cannot take.
        guard let kindByte = try read(1, startsFrame: false, timeLimit: timeLimit)?.first else {
            throw SessionProtocolError.connectionClosed
        }
        let kind = try MessageFrame.kind(fromByte: kindByte)
        try admittingFrame(MessageFrame.lengthFieldSize + length, kind)
        guard let payload = try read(length - 1, startsFrame: false, timeLimit: timeLimit) else {
            throw SessionProtocolError.connectionClosed
        }
        return try Message(frame: MessageFrame(kind: kind, payload: payload))
    }

    /// Throws `SessionProtocolError.peerIsAnotherUser` unless the program at
    /// the other end runs as `expected`. Call it before sending anything.
    public func requirePeer(_ expected: PeerIdentity = .currentUser) throws {
        let peer = try PeerIdentity(ofSocket: descriptor)
        guard peer == expected else {
            throw SessionProtocolError.peerIsAnotherUser(expected: expected.userIdentifier, found: peer.userIdentifier)
        }
    }

    /// Ends both directions at once. A thread blocked in `receive` or `send`
    /// returns. The descriptor itself closes when the last reference goes
    /// away, so a thread that still uses it never meets a reused number.
    public func shutdown() {
        Darwin.shutdown(descriptor, SHUT_RDWR)
    }

    /// Whether the other side has closed the connection. It notices the close
    /// also while bytes that were never read wait in the socket, which a read
    /// would return first.
    public var peerHasClosed: Bool {
        var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&entry, 1, 0) > 0 else { return false }
        return entry.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0
    }

    /// Reads `count` bytes. The buffer grows as the bytes arrive, so a frame
    /// that announces 64 MiB and sends little costs little.
    private func read(_ count: Int, startsFrame: Bool, timeLimit: TimeLimit) throws -> Data? {
        var bytes = Data()
        let chunk = UnsafeMutableRawBufferPointer.allocate(byteCount: max(1, min(count, Self.readChunkSize)), alignment: 1)
        defer { chunk.deallocate() }
        var lastProgress = ContinuousClock.now
        while bytes.count < count {
            let waitLimit: Duration?
            switch timeLimit {
            case .unlimited:
                waitLimit = nil
            case .wholeFrame(let deadline):
                waitLimit = deadline - .now
            case .stall(let limit):
                waitLimit = startsFrame && bytes.isEmpty ? nil : lastProgress + limit - .now
            }
            if let waitLimit {
                guard waitLimit > .zero else {
                    throw SessionProtocolError.timedOut(waitingFor: "the rest of a frame")
                }
                // The loop checks the time again, after a signal as well.
                guard Self.wait(for: descriptor, until: Int16(POLLIN), atMost: waitLimit) else { continue }
            }
            let offset = bytes.count
            let received = Darwin.read(descriptor, chunk.baseAddress!, min(count - offset, chunk.count))
            let code = errno
            if received > 0 {
                bytes.append(chunk.baseAddress!.assumingMemoryBound(to: UInt8.self), count: received)
                lastProgress = .now
            } else if received == 0 {
                if offset == 0 && startsFrame { return nil }
                throw SessionProtocolError.connectionClosed
            } else if code == EINTR || code == EAGAIN {
                continue
            } else if code == ECONNRESET || code == EBADF || code == EINVAL {
                // The peer or a local shutdown ended the connection.
                if offset == 0 && startsFrame { return nil }
                throw SessionProtocolError.connectionClosed
            } else {
                throw SessionProtocolError.systemCallFailed(function: "read", code: code)
            }
        }
        return bytes
    }

    /// Waits until the socket is ready or the time passes. Returns whether
    /// it became ready. A local `shutdown` makes it ready.
    private static func wait(for descriptor: Int32, until events: Int16, atMost limit: Duration) -> Bool {
        let parts = limit.components
        // Rounded up, so the wait never ends before the time is over.
        let milliseconds = parts.seconds * 1000 + (parts.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
        var entry = pollfd(fd: descriptor, events: events, revents: 0)
        return poll(&entry, 1, Int32(clamping: milliseconds)) > 0
    }

    /// Sets how long a send may wait without progress. Nil waits forever.
    private static func setSendTimeout(_ limit: Duration?, on descriptor: Int32) {
        var time = timeval(tv_sec: 0, tv_usec: 0)
        if let limit {
            // A zero timeout means none, so the shortest limit is a millisecond.
            let parts = max(limit, .milliseconds(1)).components
            time = timeval(tv_sec: Int(parts.seconds), tv_usec: Int32(parts.attoseconds / 1_000_000_000_000))
        }
        // This fails once the peer has closed. The send then fails at once.
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func turnOffBrokenPipeSignal(on descriptor: Int32) {
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }
}

extension MessageConnection {
    /// The client side of the start of every conversation: say hello, and
    /// check that the session process speaks the same protocol version.
    ///
    /// - Parameter limit: The time that the answer may take. Nil waits as
    ///   long as it takes. Past the limit, it throws
    ///   `SessionProtocolError.timedOut`.
    public func greetSessionProcess(within limit: Duration? = nil) throws {
        let deadline = limit.map { ContinuousClock.now + $0 }
        // A session process that refuses this client answers and closes at
        // once, maybe before the hello goes out. Its answer still waits here
        // and explains more than the failed write.
        var sendError: (any Error)?
        do {
            try send(ClientMessage.hello(protocolVersion: MessageFrame.protocolVersion), stallLimit: limit)
        } catch {
            sendError = error
        }
        let answer: ServerMessage?
        do {
            answer = try receive(ServerMessage.self, timeLimit: deadline.map { .wholeFrame(by: $0) } ?? .unlimited)
        } catch {
            throw sendError ?? error
        }
        switch answer {
        case .hello(let version):
            guard version == MessageFrame.protocolVersion else {
                throw SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: version)
            }
        case .failure(let failure) where failure.reason == .incompatibleProtocol:
            guard let version = Self.version(inRefusal: failure.message) else {
                throw SessionProtocolError.refused(message: failure.message)
            }
            throw SessionProtocolError.incompatibleVersion(ours: MessageFrame.protocolVersion, theirs: version)
        case .failure(let failure):
            throw SessionProtocolError.refused(message: failure.message)
        case .none:
            throw sendError ?? SessionProtocolError.connectionClosed
        case .some(let other):
            // The name only: a whole message can be a screen of 64 MiB.
            throw SessionProtocolError.unexpectedMessage(description: "\(other.name) arrived instead of hello")
        }
    }

    /// The message of the failure that refuses a client of another version.
    /// Every version must keep the words "protocol version" and the number of
    /// the session process after them, because a client reads the number.
    static func versionRefusal(ours: Int, theirs: Int) -> String {
        "This session process speaks protocol version \(ours), not \(theirs)."
    }

    /// The version of the session process in its refusal, or nil.
    static func version(inRefusal message: String) -> Int? {
        guard let range = message.range(of: "protocol version ") else { return nil }
        return Int(message[range.upperBound...].prefix { $0.isASCII && $0.isNumber })
    }
}
