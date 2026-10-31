/// Holds the output and size changes that the view has not applied.
final class TerminalOutputQueue {
    private final class Entry {
        let event: TerminalOutputEvent
        let completion: (@Sendable () -> Void)?
        var next: Entry?
        init(_ event: TerminalOutputEvent, completion: (@Sendable () -> Void)?) {
            self.event = event
            self.completion = completion
        }
    }

    private var firstEntry: Entry?
    private var lastEntry: Entry?
    var first: TerminalOutputEvent? { firstEntry?.event }

    func append(_ event: TerminalOutputEvent, completion: (@Sendable () -> Void)? = nil) {
        let entry = Entry(event, completion: completion)
        if let lastEntry { lastEntry.next = entry } else { firstEntry = entry }
        lastEntry = entry
    }

    func removeFirst() {
        guard let entry = firstEntry else { preconditionFailure("The output queue is empty.") }
        firstEntry = entry.next
        entry.next = nil
        if firstEntry == nil { lastEntry = nil }
        entry.completion?()
    }

    deinit {
        // Release a long backlog one entry at a time, without a deep chain of deinits.
        while firstEntry != nil { removeFirst() }
    }
}
