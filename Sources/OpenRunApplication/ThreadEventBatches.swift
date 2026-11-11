import SessionConnection
import Synchronization

/// The events of an attached thread that wait for the main thread. The
/// receiving thread adds them, and the main thread takes every event that
/// waits in one step, so a burst of streamed text costs one update of the
/// chat and not one for each piece.
final class ThreadEventBatches: Sendable {
    private let waiting = Mutex<[ThreadAttachment.Event]>([])

    /// Adds an event. Returns whether no event waited before, so the
    /// caller wakes the main thread once for each batch.
    func add(_ event: ThreadAttachment.Event) -> Bool {
        waiting.withLock { waiting in
            waiting.append(event)
            return waiting.count == 1
        }
    }

    func takeAll() -> [ThreadAttachment.Event] {
        waiting.withLock { waiting in
            defer { waiting = [] }
            return waiting
        }
    }
}
