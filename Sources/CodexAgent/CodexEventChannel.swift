import AgentConversation
import Synchronization

/// The events of one thread, from the reader of the app-server to the
/// caller, in order.
///
/// The reader waits while more than `limit` events wait. A caller that
/// reads slowly thus slows the reading of the pipe, and the memory stays
/// bounded. Events that OpenRun makes itself, such as a sent message, go
/// in without a wait.
final class CodexEventChannel: Sendable {
    struct State {
        var events: [ConversationEvent] = []
        var isFinished = false
        var reader: CheckedContinuation<ConversationEvent?, Never>?
        var writers: [CheckedContinuation<Void, Never>] = []
    }

    let limit: Int
    let state = Mutex(State())

    init(limit: Int) {
        self.limit = limit
    }

    /// Adds an event, and waits while too many wait. After the finish, the
    /// event goes nowhere.
    func send(_ event: ConversationEvent) async {
        guard add(event) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waits = state.withLock { state in
                guard state.events.count > limit, !state.isFinished else { return false }
                state.writers.append(continuation)
                return true
            }
            if !waits { continuation.resume() }
        }
    }

    /// Adds an event without a wait, and tells if too many events wait.
    @discardableResult
    func add(_ event: ConversationEvent) -> Bool {
        state.withLock { state in
            guard !state.isFinished else { return false }
            if let reader = state.reader {
                state.reader = nil
                reader.resume(returning: event)
            } else {
                state.events.append(event)
            }
            return state.events.count > limit
        }
    }

    /// Ends the channel. The caller still gets the events that wait.
    func finish() {
        state.withLock { state in
            state.isFinished = true
            state.reader?.resume(returning: nil)
            state.reader = nil
            for writer in state.writers { writer.resume() }
            state.writers = []
        }
    }

    /// The next event, or nil after the finish and the last event. Only
    /// one task may wait at a time.
    func next() async -> ConversationEvent? {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                if !state.events.isEmpty {
                    continuation.resume(returning: state.events.removeFirst())
                    if state.events.count <= limit {
                        for writer in state.writers { writer.resume() }
                        state.writers = []
                    }
                } else if state.isFinished || state.reader != nil {
                    continuation.resume(returning: nil)
                } else {
                    state.reader = continuation
                }
            }
        }
    }

    /// The events as a stream for one caller.
    var stream: AsyncStream<ConversationEvent> {
        AsyncStream(unfolding: { await self.next() })
    }
}
