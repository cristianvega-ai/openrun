import Foundation
import SessionProtocol
import Synchronization

/// The connection on which a client follows the sessions: the present list
/// first, and then each change and each end, for as long as it stays open
/// (decision of 2026-11-10). The connection keeps the session process
/// from its idle exit, like every connection.
public final class SessionChangeReceiver: Sendable {
    /// What the session process tells the client. `sessions` comes first,
    /// once, and `closed` or `failed` last. A session process that offers
    /// projects and settings sends `projects` and `settings` right after
    /// `sessions`, and again after each change of them.
    public enum Event: Equatable, Sendable {
        /// Every session at the start, oldest first.
        case sessions([SessionSummary])
        /// A new session, or new facts of a session.
        case sessionChanged(SessionSummary)
        /// The session ended and left the list.
        case sessionEnded(UUID)
        /// The whole list of projects, as `SessionClient.projects()` gives it.
        case projects([ProjectSummary])
        /// Every setting, as `SessionClient.settings()` gives them.
        case settings([SettingSummary])
        /// Every agent thread, oldest first, once after the settings, from
        /// a session process that keeps threads.
        case threads([ThreadSummary])
        /// A new thread, or new facts of a thread.
        case threadChanged(ThreadSummary)
        /// The thread closed and left the list.
        case threadEnded(UUID)
        case closed
        case failed(SessionConnectionError)
    }

    /// Whether the client asked for the agent threads. Their list then
    /// comes one time, after the settings.
    public let includesThreads: Bool
    private let connection: MessageConnection
    private let initialList: [SessionSummary]
    private let isReceiving = Atomic<Bool>(false)

    private init(connection: MessageConnection, initialList: [SessionSummary], includesThreads: Bool) {
        (self.connection, self.initialList, self.includesThreads) = (connection, initialList, includesThreads)
    }

    /// Asks for the changes, and returns once the present list is there.
    ///
    /// - Parameter includesThreads: Asks for the agent threads too. Only a
    ///   session process with the capability `threads` knows them.
    static func open(on connection: MessageConnection, includesThreads: Bool = false) throws -> SessionChangeReceiver {
        let request = ClientMessage.receiveSessionChanges(includesThreads: includesThreads ? true : nil)
        try SessionConnectionError.wrapping { try connection.send(request) }
        switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
        case .sessionList(let list): return SessionChangeReceiver(connection: connection, initialList: list, includesThreads: includesThreads)
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
                case .projectList(let projects): handler(.projects(projects))
                case .settingList(let settings): handler(.settings(settings))
                case .threadList(let threads): handler(.threads(threads))
                case .threadChanged(let thread): handler(.threadChanged(thread))
                case .threadEnded(let identifier): handler(.threadEnded(identifier))
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
        try SessionChangeReceiver.open(on: connection, includesThreads: capabilities.threads)
    }
}
