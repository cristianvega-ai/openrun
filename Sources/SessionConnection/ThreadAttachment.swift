import AgentConversation
import Foundation
import SessionProtocol
import Synchronization

/// A connection that is attached to one agent thread. It gives the events
/// that the thread kept, the mark that they are complete, and then each
/// new event. Any thread may send, also while another thread sends.
public final class ThreadAttachment: Sendable {
    /// What the session process tells the client, in order. `closed` or
    /// `failed` comes last.
    public enum Event: Equatable, Sendable {
        case event(ConversationEvent)
        /// The events before this mark came before the attach. `true`
        /// tells that older events went away, so the history holds more.
        case replayComplete(hasEarlierEvents: Bool)
        /// The thread took a message that this connection sent.
        case messageSent(UUID)
        /// The session process refused a request of this connection.
        case requestFailed(SessionFailure)
        /// The thread closed. `closed` follows.
        case threadEnded
        case closed
        case failed(SessionConnectionError)
    }

    /// The thread at the moment of the attach.
    public let summary: ThreadSummary
    let connection: MessageConnection
    let isReceiving = Atomic<Bool>(false)

    private init(connection: MessageConnection, summary: ThreadSummary) {
        (self.connection, self.summary) = (connection, summary)
    }

    /// Sends `attachThread` and waits for `threadAttached`. A failure in
    /// its place ends the attach before the caller changes anything.
    static func attach(on connection: MessageConnection, to identifier: UUID) throws -> ThreadAttachment {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.attachThread(identifier: identifier)) }
        switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
        case .threadAttached(let summary): return ThreadAttachment(connection: connection, summary: summary)
        case .failure(let failure): throw SessionConnectionError.requestFailed(failure)
        case nil: throw SessionConnectionError.connectionClosed
        default: throw SessionConnectionError.unexpectedAnswer(request: "attachThread")
        }
    }

    /// Sends a message of the user. The answer comes as `messageSent` or
    /// `requestFailed` among the events.
    public func send(message text: String, images: [ThreadImage] = []) throws {
        let message = ClientMessage.sendThreadMessage(identifier: summary.identifier, text: text, images: images.isEmpty ? nil : images)
        try SessionConnectionError.wrapping { try connection.send(message) }
    }

    /// Stops the turn of the thread.
    public func stop() throws {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.stopThread(identifier: summary.identifier)) }
    }

    public func detach() throws {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.detach) }
    }

    /// Ends the connection and wakes the receiving thread.
    public func shutdown() {
        connection.shutdown()
    }
}
