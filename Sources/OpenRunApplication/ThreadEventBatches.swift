import Foundation
import SessionConnection

/// The events of an attached thread that wait for the main thread. The
/// receiving thread adds them, and the main thread takes every event that
/// waits in one step, so a burst of streamed text costs one update of the
/// chat and not one for each piece.
///
/// The condition guards every stored property, so the class is safe to
/// share although the compiler cannot check the lock.
final class ThreadEventBatches: @unchecked Sendable {
    private let condition = NSCondition()
    private var waiting: [ThreadAttachment.Event] = []
    /// The bounds of the events that wait. A full stage holds the reader,
    /// so the socket and the session process hold the later events.
    private let limit = 4_096
    private let byteLimit = 4 * 1024 * 1024
    private var bytes = 0
    private var isClosed = false

    /// Adds an event of `size` bytes. Returns whether no event waited
    /// before, so the caller wakes the main thread once for each batch.
    func add(_ event: ThreadAttachment.Event, size: Int = 0) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while !isClosed && (waiting.count >= limit || (!waiting.isEmpty && bytes + size > byteLimit)) { condition.wait() }
        guard !isClosed else { return false }
        waiting.append(event)
        bytes += size
        return waiting.count == 1
    }

    func takeAll() -> [ThreadAttachment.Event] {
        condition.lock()
        defer { condition.unlock() }
        let result = waiting
        waiting.removeAll(keepingCapacity: true)
        bytes = 0
        condition.broadcast()
        return result
    }

    /// Wakes a reader that waits for room, and refuses later events,
    /// when the pane closes or its connection ends.
    func close() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }
}
