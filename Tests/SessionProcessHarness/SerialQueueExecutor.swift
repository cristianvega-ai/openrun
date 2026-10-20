import Dispatch

/// Runs the jobs of one test on a serial dispatch queue of its own. A serial
/// queue without a target gets a new thread when the other threads are busy,
/// so a test that blocks its thread blocks only itself. The threads of Swift
/// concurrency, one for each processor core, stay free for everyone else.
final class SerialQueueExecutor: TaskExecutor {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}
