import Foundation
import SessionProtocol
import Synchronization

/// A connection that is attached to one session. It starts with the
/// snapshot of the terminal of the session. Any thread may send, also while
/// another thread sends: each message goes out whole.
public final class SessionAttachment: Sendable {
    /// The terminal of the session at the moment of the attach, as the protocol
    /// carries it. `TerminalSnapshot(bytes:)` restores it. Output comes after it.
    public let snapshot: Data
    /// The attach command of the tool receives and sends on the connection
    /// itself until it uses the calls below.
    package let connection: MessageConnection
    private let isReceiving = Atomic<Bool>(false)

    init(connection: MessageConnection, snapshot: Data) {
        self.connection = connection
        self.snapshot = snapshot
    }

    /// Sends `attach` and waits for `attached` and the snapshot. A failure in
    /// their place ends the attach before the caller changes anything.
    static func attach(on connection: MessageConnection, to identifier: UUID, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool) throws -> SessionAttachment {
        // A flag that is off stays out of the message. Every session process
        // reads that as off, and the tool sends the message that it sent before.
        let message = ClientMessage.attach(identifier: identifier, size: size, relaysRawOutput: relaysRawOutput ? true : nil, receivesSizeChanges: receivesSizeChanges ? true : nil)
        try SessionConnectionError.wrapping { try connection.send(message) }
        for _ in 0..<2 {
            switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
            case .attached:
                continue
            case .snapshot(let bytes):
                return SessionAttachment(connection: connection, snapshot: bytes)
            case .failure(let failure):
                throw SessionConnectionError.requestFailed(failure)
            default:
                throw SessionConnectionError.unexpectedAttachAnswer
            }
        }
        throw SessionConnectionError.missingSnapshot
    }

    /// Sends keys to the session in one input frame. It waits while the
    /// session process holds as much input as it may, because the program
    /// reads none.
    public func send(input: Data) throws {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.input(input)) }
    }

    /// Sends the size of this client. The client that sends a size last sets
    /// the size of the session.
    public func send(size: SessionSize) throws {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.resize(size)) }
    }

    /// Asks the session process to detach this client. The session goes on.
    public func detach() throws {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.detach) }
    }

    /// Ends both directions of the connection at once. The receiving thread
    /// then ends with `closed` or `failed`, and a send that waits returns.
    public func shutdown() {
        connection.shutdown()
    }

    /// Starts the thread that receives the events of the session. It hands
    /// each one to `handler` in order, and ends after `exited`, `closed` or
    /// `failed`. While `handler` runs, the socket holds the later events, so
    /// a caller on the main thread hands each event on to the main queue.
    /// Only the first call starts a thread.
    public func startReceiving(_ handler: @escaping @Sendable (SessionAttachmentEvent) -> Void) {
        guard !isReceiving.exchange(true, ordering: .acquiringAndReleasing) else { return }
        let receiver = Thread { [connection] in
            Self.receiveEvents(on: connection, into: handler)
        }
        receiver.name = "attach.receiver"
        receiver.start()
    }

    private static func receiveEvents(on connection: MessageConnection, into handler: (SessionAttachmentEvent) -> Void) {
        while true {
            let message: ServerMessage?
            do {
                message = try connection.receive(ServerMessage.self)
            } catch {
                // Only the decoding of a frame can throw another type of error.
                handler(.failed(.protocolFailure(error as? SessionProtocolError ?? .malformedFrame(reason: "\(error)"))))
                return
            }
            switch message {
            case .output(let bytes):
                handler(.output(bytes))
            case .sizeChanged(let size):
                handler(.sizeChanged(size))
            case .exited(let exit):
                handler(.exited(exit))
                return
            case nil:
                handler(.closed)
                return
            default:
                // No other message belongs after the snapshot.
                continue
            }
        }
    }
}
