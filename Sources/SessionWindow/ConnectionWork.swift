import Dispatch

/// Runs the calls of one window that wait for the socket, on a serial queue.
/// The main thread must never wait: a connection can wake the launch agent,
/// and a send waits while the program reads no input. The queue keeps the
/// order of keys and sizes, and a detach goes behind the keys before it.
final class ConnectionWork: Sendable {
    private let queue = DispatchQueue(label: "ai.cristianvega.openrun.window-connection")

    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Runs `work` on the queue, and then gives its result to `finish` on the main thread.
    func run<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value, then finish: @escaping @MainActor @Sendable (Result<Value, any Error>) -> Void) {
        queue.async {
            let result = Result { try work() }
            DispatchQueue.main.async { MainActor.assumeIsolated { finish(result) } }
        }
    }
}
