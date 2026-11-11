import Dispatch
import Synchronization

/// Runs the calls of one pane that wait for the socket, on a serial queue.
/// The main thread must never wait: a connection can wake the launch agent,
/// and a send waits while the program reads no input. The queue keeps the
/// order of keys and sizes. An independent shutdown can free a stalled send.
final class ConnectionWork: Sendable {
    private let queue = DispatchQueue(label: "ai.cristianvega.openrun.window-connection")
    private let isStopped = Mutex(false)

    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard !isStopped.withLock({ $0 }) else { return }
            work()
        }
    }

    /// Lets ready input and a detach go out, but wakes a stalled send after 200 ms.
    func detach(_ attachment: any AttachedSession) {
        queue.async { [self] in
            if !isStopped.withLock({ $0 }) { try? attachment.detach() }
            shutdown(attachment)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) { [self] in
            shutdown(attachment)
        }
    }

    /// Ends the transport independently of the queue, and skips its remaining sends.
    func shutdown(_ attachment: any AttachedSession) {
        let first = isStopped.withLock { stopped in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        if first { attachment.shutdown() }
    }

    /// Runs `work` on the queue, and then gives its result to `finish` on the main thread.
    func run<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value, then finish: @escaping @MainActor @Sendable (Result<Value, any Error>) -> Void) {
        queue.async {
            let result = Result { try work() }
            DispatchQueue.main.async { MainActor.assumeIsolated { finish(result) } }
        }
    }
}
