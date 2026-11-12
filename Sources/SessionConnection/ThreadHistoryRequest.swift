import AgentConversation
import Foundation
import SessionProtocol

/// The earlier turns of a thread, which the session process reads from
/// the history of the agent (proposal 3).
extension SessionClient {
    /// A page of the earlier turns of a thread, from the history of its
    /// agent: the events of whole turns, oldest first.
    ///
    /// - Parameters:
    ///   - before: The `before` of the page that the caller has, or nil
    ///     for the newest page.
    ///   - cursor: The `cursor` of that page, which a Codex thread gives
    ///     in place of `before`.
    /// - Returns: The events, and the `before` or the `cursor` of the
    ///   page before them. Both are nil at the start of the history.
    public func threadHistory(_ identifier: UUID, before: Int? = nil, cursor: String? = nil) throws -> (events: [ConversationEvent], before: Int?, cursor: String?) {
        let request = ClientMessage.readThreadHistory(identifier: identifier, before: before, cursor: cursor)
        try SessionConnectionError.wrapping { try connection.send(request) }
        var events: [ConversationEvent] = []
        let decoder = JSONDecoder()
        while true {
            switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
            // An event that this build cannot read is left out.
            case .threadEvent(let data): if let event = try? decoder.decode(ConversationEvent.self, from: data) { events.append(event) }
            case .threadHistoryPage(let before, let cursor): return (events, before, cursor)
            case .failure(let failure): throw SessionConnectionError.requestFailed(failure)
            case nil: throw SessionConnectionError.connectionClosed
            default: throw SessionConnectionError.unexpectedAnswer(request: "thread history")
            }
        }
    }
}
