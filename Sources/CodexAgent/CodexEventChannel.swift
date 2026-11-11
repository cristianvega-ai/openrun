import AgentConversation
import Synchronization

/// The events of one thread, from the reader of the app-server to the
/// caller, in order.
///
/// The reader never waits for the caller, so that a thread that nobody
/// reads cannot hold back the answers of the other threads. At most
/// `limit` events and `byteLimit` bytes wait, and the pieces of one
/// streamed item count as one event. The app-server ends a thread whose
/// caller lets more wait, and the memory stays bounded.
final class CodexEventChannel: Sendable {
    struct State {
        var events: [ConversationEvent] = []
        /// The room of each event that waits, and of all of them.
        var sizes: [Int] = []
        var waitingBytes = 0
        var isFinished = false
        var reader: CheckedContinuation<ConversationEvent?, Never>?
    }

    let limit: Int
    let byteLimit: Int
    let state = Mutex(State())

    init(limit: Int, byteLimit: Int = .max) {
        self.limit = limit
        self.byteLimit = byteLimit
    }

    /// Adds an event without a wait. Returns false, and adds nothing, when
    /// the event does not fit in the limits. One event of any size can
    /// wait alone, because one line can be larger than `byteLimit`. After
    /// the finish, the event goes nowhere.
    @discardableResult
    func add(_ event: ConversationEvent) -> Bool {
        state.withLock { state in
            guard !state.isFinished else { return true }
            let size = CodexEventPieces.byteCount(of: event)
            guard state.events.isEmpty || size <= byteLimit - state.waitingBytes else { return false }
            if let reader = state.reader, limit > 0 {
                state.reader = nil
                reader.resume(returning: event)
            } else if let last = state.events.last, let joined = CodexEventPieces.joined(last, event) {
                state.events[state.events.count - 1] = joined
                state.sizes[state.sizes.count - 1] += size
                state.waitingBytes += size
            } else {
                guard state.events.count < limit else { return false }
                state.events.append(event)
                state.sizes.append(size)
                state.waitingBytes += size
            }
            return true
        }
    }

    /// Ends the channel, after a last event above the limit. The caller
    /// still gets the events that wait.
    func finish(with last: ConversationEvent? = nil) {
        state.withLock { state in
            guard !state.isFinished else { return }
            state.isFinished = true
            if let last, let reader = state.reader {
                state.reader = nil
                reader.resume(returning: last)
            } else if let last {
                state.events.append(last)
                state.sizes.append(0)
            }
            state.reader?.resume(returning: nil)
            state.reader = nil
        }
    }

    /// The next event, or nil after the finish and the last event. Only
    /// one task may wait at a time.
    func next() async -> ConversationEvent? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.withLock { state in
                    if !state.events.isEmpty {
                        state.waitingBytes -= state.sizes.removeFirst()
                        continuation.resume(returning: state.events.removeFirst())
                    } else if state.isFinished || state.reader != nil || Task.isCancelled {
                        continuation.resume(returning: nil)
                    } else {
                        state.reader = continuation
                    }
                }
            }
        } onCancel: {
            state.withLock { state in
                state.reader?.resume(returning: nil)
                state.reader = nil
            }
        }
    }

    /// The events as a stream for one caller.
    var stream: AsyncStream<ConversationEvent> {
        AsyncStream(unfolding: { await self.next() })
    }
}
