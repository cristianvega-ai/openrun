import AgentConversation
import Foundation
import SessionProtocol

/// The earlier turns of a thread, which the session process reads from
/// the history of the agent (proposal 3).
extension SessionClient {
    /// A page of the earlier turns of a thread, from the history of its
    /// agent: the events of whole turns, oldest first.
    ///
    /// - Parameter before: The `before` of the page that the caller has,
    ///   or nil for the newest page.
    /// - Returns: The events, and the `before` of the page before them,
    ///   which is nil at the start of the history.
    public func threadHistory(_ identifier: UUID, before: Int? = nil) throws -> (events: [ConversationEvent], before: Int?) {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.readThreadHistory(identifier: identifier, before: before)) }
        var events: [ConversationEvent] = []
        let decoder = JSONDecoder()
        while true {
            switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
            // An event that this build cannot read is left out.
            case .threadEvent(let data): if let event = try? decoder.decode(ConversationEvent.self, from: data) { events.append(event) }
            case .threadHistoryPage(let before): return (events, before)
            case .failure(let failure): throw SessionConnectionError.requestFailed(failure)
            case nil: throw SessionConnectionError.connectionClosed
            default: throw SessionConnectionError.unexpectedAnswer(request: "thread history")
            }
        }
    }
}
