import AgentConversation
import Foundation
import SessionProtocol

/// The receiving side of a thread attachment.
extension ThreadAttachment {
    /// Starts the thread that hands each event to `handler` in order.
    /// Only the first call starts a thread. While the handler runs, the
    /// socket holds the later events.
    public func startReceiving(_ handler: @escaping @Sendable (Event) -> Void) {
        guard !isReceiving.exchange(true, ordering: .acquiringAndReleasing) else { return }
        let receiver = Thread { [self] in receive(handler) }
        receiver.name = "thread.attachment.receiver"
        receiver.start()
    }

    private func receive(_ handler: @Sendable (Event) -> Void) {
        let decoder = JSONDecoder()
        while true {
            let message: ServerMessage?
            do {
                message = try connection.receive(ServerMessage.self)
            } catch {
                return handler(.failed(.protocolFailure(error as? SessionProtocolError ?? .malformedFrame(reason: "\(error)"))))
            }
            switch message {
            case .threadEvent(let data):
                // An event that this build cannot read is left out, and the next one is read as usual.
                if let event = try? decoder.decode(ConversationEvent.self, from: data) { handler(.event(event)) }
            case .threadReplayComplete(let hasEarlierEvents): handler(.replayComplete(hasEarlierEvents: hasEarlierEvents))
            case .threadMessageSent(let identifier): handler(.messageSent(identifier))
            case .failure(let failure): handler(.requestFailed(failure))
            case .threadEnded: handler(.threadEnded)
            case nil: return handler(.closed)
            default: continue
            }
        }
    }
}
