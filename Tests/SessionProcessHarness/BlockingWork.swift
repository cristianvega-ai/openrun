import Foundation

/// Runs work that blocks a thread, such as a read with a watchdog, on a new
/// thread. An unstructured task would run it on a thread of Swift
/// concurrency, which other tests need, and not on the thread of its test.
public enum BlockingWork {
    public static func onNewThread<Value: Sendable, Failure: Error>(
        _ work: @escaping @Sendable () throws(Failure) -> Value
    ) async throws(Failure) -> Value {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Value, Failure>, Never>) in
            Thread { continuation.resume(returning: Result(catching: work)) }.start()
        }
        return try result.get()
    }
}
