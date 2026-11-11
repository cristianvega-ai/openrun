import Foundation
import SessionProtocol
import Synchronization

/// The connection on which a client follows the sessions: the present list
/// first, and then each change and each end, for as long as it stays open
/// (decision of 2026-11-10). The connection keeps the session process
/// from its idle exit, like every connection.
public final class SessionChangeReceiver: Sendable {
    /// What the session process tells the client. `sessions` comes first,
    /// once, and `closed` or `failed` last. Later kinds of change, such as the
    /// projects, come as further cases.
    public enum Event: Equatable, Sendable {
        /// Every session at the start, oldest first.
        case sessions([SessionSummary])
        /// A new session, or new facts of a session.
        case sessionChanged(SessionSummary)
        /// The session ended and left the list.
        case sessionEnded(UUID)
        case closed
        case failed(SessionConnectionError)
    }

    private let connection: MessageConnection
    private let initialList: [SessionSummary]
    private let isReceiving = Atomic<Bool>(false)

    private init(connection: MessageConnection, initialList: [SessionSummary]) {
        self.connection = connection
        self.initialList = initialList
    }

    /// Asks for the changes, and returns once the present list is there.
    static func open(on connection: MessageConnection) throws -> SessionChangeReceiver {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.receiveSessionChanges) }
        switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
        case .sessionList(let list): return SessionChangeReceiver(connection: connection, initialList: list)
        case .failure(let failure): throw SessionConnectionError.requestFailed(failure)
        case nil: throw SessionConnectionError.connectionClosed
        default: throw SessionConnectionError.unexpectedAnswer(request: "receiveSessionChanges")
        }
    }

    /// Ends the connection. The thread then hands `closed` or `failed` to
    /// the handler and returns.
    public func shutdown() {
        connection.shutdown()
    }

    /// Starts the thread that hands each event to `handler` in order, first
    /// `sessions`. Only the first call starts a thread. While the handler
    /// runs, the socket holds the later changes.
    public func startReceiving(_ handler: @escaping @Sendable (Event) -> Void) {
        guard !isReceiving.exchange(true, ordering: .acquiringAndReleasing) else { return }
        let receiver = Thread { [self] in
            handler(.sessions(initialList))
            while true {
                let message: ServerMessage?
                do {
                    message = try connection.receive(ServerMessage.self)
                } catch {
                    handler(.failed(.protocolFailure(error as? SessionProtocolError ?? .malformedFrame(reason: "\(error)"))))
                    return
                }
                switch message {
                case .sessionChanged(let summary): handler(.sessionChanged(summary))
                case .sessionEnded(let identifier): handler(.sessionEnded(identifier))
                case .failure(let failure): return handler(.failed(.requestFailed(failure)))
                case nil: return handler(.closed)
                default: continue
                }
            }
        }
        receiver.name = "session.changes.receiver"
        receiver.start()
    }
}

extension SessionClient {
    /// Turns the connection into one that follows the sessions. The client
    /// takes no more requests. Check `capabilities.sessionChanges` first: an
    /// older session process refuses the request.
    public func receiveSessionChanges() throws -> SessionChangeReceiver {
        try SessionChangeReceiver.open(on: connection)
    }
}
