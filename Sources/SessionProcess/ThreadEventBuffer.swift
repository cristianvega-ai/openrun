import AgentConversation
import Foundation

/// The newest events of a thread, for a client that attaches (decision of
/// 2026-11-10). OpenRun keeps no lasting copy of the events: the earlier
/// turns come from the history of the agent (proposal 3).
///
/// The buffer holds at most `byteLimit` bytes. Whole turns go first, the
/// oldest one first, so that the events that stay start at the start of a
/// turn and give a transcript with no half item. Only a turn that is
/// larger than the limit by itself loses its oldest events.
struct ThreadEventBuffer {
    /// The most bytes of the events of one thread.
    static let defaultByteLimit = 4 * 1024 * 1024

    struct Entry {
        /// The event as the JSON that a client gets.
        let data: Data
        let endsTurn: Bool
    }

    let byteLimit: Int
    private(set) var entries: [Entry] = []
    private(set) var byteCount = 0
    /// Whether events went away, so that the buffer no longer starts at
    /// the first event since the thread came into use.
    private(set) var hasEarlierEvents = false
    private let encoder = JSONEncoder()

    init(byteLimit: Int = ThreadEventBuffer.defaultByteLimit) {
        self.byteLimit = byteLimit
    }

    /// Keeps the event and returns it as the JSON for the clients.
    mutating func append(_ event: ConversationEvent) -> Data {
        let data = (try? encoder.encode(event)) ?? Data("{}".utf8)
        let endsTurn = if case .turnEnded = event.kind { true } else { false }
        entries.append(Entry(data: data, endsTurn: endsTurn))
        byteCount += data.count
        trim()
        return data
    }

    private mutating func trim() {
        while byteCount > byteLimit, entries.count > 1 {
            // The newest event always stays, also when it is larger than the limit.
            let turnEnd = entries.dropLast().firstIndex { $0.endsTurn }
            let count = turnEnd.map { $0 + 1 } ?? 1
            byteCount -= entries.prefix(count).reduce(0) { $0 + $1.data.count }
            entries.removeFirst(count)
            hasEarlierEvents = true
        }
    }
}
