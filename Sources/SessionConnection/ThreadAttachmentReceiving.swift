import AgentConversation
import Foundation
import SessionProtocol

/// The receiving side of a thread attachment.
extension ThreadAttachment {
    /// Starts the thread that hands each event to `handler` in order.
    /// Only the first call starts a thread. While the handler runs, the
    /// socket holds the later events.
    public func startReceiving(_ handler: @escaping @Sendable (Event) -> Void) {
        startReceiving { event, _ in handler(event) }
    }

    /// As `startReceiving(_:)`, with the size of the frame of each event,
    /// so that a receiver can bound its memory without a new encode.
    public func startReceiving(measuring handler: @escaping @Sendable (Event, _ byteCount: Int) -> Void) {
        guard !isReceiving.exchange(true, ordering: .acquiringAndReleasing) else { return }
        let receiver = Thread { [self] in receive(handler) }
        receiver.name = "thread.attachment.receiver"
        receiver.start()
    }

    private func receive(_ handler: @Sendable (Event, Int) -> Void) {
        let decoder = JSONDecoder()
        while true {
            let message: ServerMessage?
            do {
                message = try connection.receive(ServerMessage.self)
            } catch {
                return handler(.failed(.protocolFailure(error as? SessionProtocolError ?? .malformedFrame(reason: "\(error)"))), 0)
            }
            switch message {
            case .threadEvent(let data):
                // An event that this build cannot read is left out, and the next one is read as usual.
                if let event = try? decoder.decode(ConversationEvent.self, from: data) { handler(.event(event), data.count) }
            case .threadReplayComplete(let hasEarlierEvents): handler(.replayComplete(hasEarlierEvents: hasEarlierEvents), 0)
            case .threadMessageSent(let identifier): handler(.messageSent(identifier), 0)
            case .failure(let failure): handler(.requestFailed(failure), failure.message.utf8.count)
            case .threadEnded: handler(.threadEnded, 0)
            case nil: return handler(.closed, 0)
            default: continue
            }
        }
    }
}
