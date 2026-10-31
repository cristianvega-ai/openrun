import Foundation
import SessionConnection

/// Bounds the events between the socket and the terminal parser.
final class AttachmentRelay: @unchecked Sendable {
    private let condition = NSCondition()
    private let byteLimit: Int
    private let eventLimit: Int
    private var pendingBytes = 0
    private var pendingEvents = 0
    private var isCancelled = false

    init(byteLimit: Int = 1024 * 1024, eventLimit: Int = 128) {
        precondition(byteLimit > 0 && eventLimit > 0)
        self.byteLimit = byteLimit
        self.eventLimit = eventLimit
    }

    /// The receiver waits for room. One large frame may enter an empty relay.
    /// A protocol frame is at most 64 MiB. The receiver can hold one more
    /// frame while it waits, and the parser copies an admitted output frame.
    func handler(_ deliver: @escaping @MainActor @Sendable (SessionAttachmentEvent, @escaping @Sendable () -> Void) -> Void) -> @Sendable (SessionAttachmentEvent) -> Void {
        { [self] event in
            let bytes: Int
            if case .output(let output) = event { bytes = output.count } else { bytes = 0 }
            condition.lock()
            while !isCancelled && (pendingEvents >= eventLimit || (pendingEvents > 0 && (bytes > byteLimit || pendingBytes > byteLimit - bytes))) {
                condition.wait()
            }
            guard !isCancelled else { condition.unlock(); return }
            pendingEvents += 1
            pendingBytes += bytes
            condition.unlock()
            DispatchQueue.main.async { [self] in
                condition.lock()
                let cancelled = isCancelled
                condition.unlock()
                if cancelled { finish(bytes); return }
                MainActor.assumeIsolated { deliver(event) { self.finish(bytes) } }
            }
        }
    }

    /// A close must wake the receiver even when the parser cannot make room.
    func cancel() {
        condition.lock()
        isCancelled = true
        condition.broadcast()
        condition.unlock()
    }

    private func finish(_ bytes: Int) {
        condition.lock()
        pendingEvents -= 1
        pendingBytes -= bytes
        condition.broadcast()
        condition.unlock()
    }
}
