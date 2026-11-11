import Foundation

/// Which threads may run the process of an agent now. At most eight run
/// at one time (decision of 2026-11-10), because one idle Claude Code
/// uses 300 to 400 MB of memory.
struct AgentProcessSlots {
    static let defaultLimit = 8

    private(set) var limit: Int
    /// The threads whose agent runs or starts.
    private(set) var holders: Set<UUID> = []
    /// The threads whose message waits for a slot. The longest wait is first.
    private(set) var waiting: [UUID] = []

    init(limit: Int = AgentProcessSlots.defaultLimit) {
        self.limit = limit
    }

    /// Gives the thread a slot when it has one or when one is free. Else
    /// the thread waits in line.
    mutating func take(for thread: UUID) -> Bool {
        if holders.contains(thread) { return true }
        guard holders.count < limit else {
            if !waiting.contains(thread) { waiting.append(thread) }
            return false
        }
        holders.insert(thread)
        return true
    }

    /// The agent of the thread ended. Its slot goes to the thread that
    /// waited longest, unless a lower limit took the slot away.
    ///
    /// - Returns: The thread that got the slot, which can start its agent now.
    mutating func release(_ thread: UUID) -> UUID? {
        guard holders.remove(thread) != nil, holders.count < limit, !waiting.isEmpty else { return nil }
        let next = waiting.removeFirst()
        holders.insert(next)
        return next
    }

    /// Takes the limit of newer settings. A lower limit ends no agent,
    /// and it applies to the next start.
    ///
    /// - Returns: The threads in line that got a slot of a higher limit.
    mutating func setLimit(_ newLimit: Int) -> [UUID] {
        limit = newLimit
        var granted: [UUID] = []
        while holders.count < limit, !waiting.isEmpty {
            granted.append(waiting.removeFirst())
            holders.insert(granted[granted.count - 1])
        }
        return granted
    }

    /// The thread closed: it holds no slot and waits for none.
    mutating func remove(_ thread: UUID) -> UUID? {
        waiting.removeAll { $0 == thread }
        return release(thread)
    }
}
