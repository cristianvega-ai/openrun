/// The earlier turns of a thread, which a chat takes from the history of
/// the agent, because OpenRun keeps no copy of the events (proposal 3).
extension Transcript {
    /// The start of the name of an item that has no identifier of its own
    /// and takes the number of its event.
    private static let countedPrefixes = ["turn:", "notice:", "unknown:"]

    private static func isCounted(_ identifier: String) -> Bool {
        countedPrefixes.contains { identifier.hasPrefix($0) }
    }

    /// Puts earlier turns before the items of the transcript.
    ///
    /// `events` are a page of the history of the agent, oldest first. A
    /// turn starts at a message of the user. The history also holds the
    /// turns whose live events came already, so a turn with an item that
    /// the transcript has is left out. The state of the thread does not
    /// change. When the limits have no room, the oldest items go.
    ///
    /// - Parameter label: A word that no other page has. An item with no
    ///   identifier of its own takes it with the number of its turn, so
    ///   two turns never share a name.
    /// - Returns: How many items came in and stayed.
    @discardableResult
    public mutating func prepend(history events: [ConversationEvent], label: String) -> Int {
        var earlier: [TranscriptItem] = []
        var names: Set<String> = []
        for (number, turn) in Self.turns(of: events).enumerated() {
            var page = Transcript(events: turn, limits: limits)
            // The end of a process closes what a turn without an end left open.
            page.apply(ConversationEvent(.processEnded(ProcessEnd(exitStatus: 0, wasRequested: true))))
            if page.items.contains(where: { !Self.isCounted($0.identifier) && storage.contains($0.identifier) }) { continue }
            for var item in page.items {
                if Self.isCounted(item.identifier) { item.identifier = "\(label)-\(number):\(item.identifier)" }
                if !storage.contains(item.identifier), names.insert(item.identifier).inserted { earlier.append(item) }
            }
        }
        storage.prepend(earlier)
        let removed = storage.trim(to: limits)
        forget(removed)
        return earlier.count - removed.count { names.contains($0) }
    }

    /// The events in turns: a new turn starts at each message of the user.
    static func turns(of events: [ConversationEvent]) -> [[ConversationEvent]] {
        var turns: [[ConversationEvent]] = []
        for event in events {
            if case .userMessage = event.kind { turns.append([]) }
            if turns.isEmpty { turns.append([]) }
            turns[turns.count - 1].append(event)
        }
        return turns
    }
}
