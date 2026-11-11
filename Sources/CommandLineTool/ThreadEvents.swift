import AgentConversation
import Foundation
import SessionConnection
import Synchronization

/// The events that a thread keeps, for `openrun thread read`.
enum ThreadEvents {
    /// Attaches to the thread, takes the kept events, and leaves again.
    static func kept(of thread: UUID, client: SessionClient) throws -> [ConversationEvent] {
        let attachment = try client.attachThread(thread)
        defer { attachment.shutdown() }
        let events = Mutex<[ConversationEvent]>([])
        let failure = Mutex<String?>(nil)
        let isComplete = DispatchSemaphore(value: 0)
        attachment.startReceiving { event in
            switch event {
            case .event(let event): events.withLock { $0.append(event) }
            case .replayComplete: isComplete.signal()
            case .failed(let error):
                failure.withLock { $0 = "\(error)" }
                isComplete.signal()
            case .closed, .threadEnded:
                failure.withLock { $0 = $0 ?? "The thread closed." }
                isComplete.signal()
            case .messageSent, .requestFailed: break
            }
        }
        isComplete.wait()
        if let reason = failure.withLock({ $0 }) { throw CommandLineToolError.failure(reason) }
        return events.withLock { $0 }
    }

    /// Each event as one line of JSON, in the form of the protocol.
    static func lines(of events: [ConversationEvent]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try events.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }.joined()
    }
}
