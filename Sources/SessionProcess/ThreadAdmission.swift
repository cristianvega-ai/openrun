import Synchronization

/// The gate of new thread work at the shutdown. Each piece of work holds
/// the gate while it runs. The shutdown seals the gate, so no new work
/// starts, and it waits until the work that the gate let in has ended.
/// A lock and not an actor, so a runner can take the gate with no wait.
final class ThreadAdmission: Sendable {
    private struct State {
        var isOpen = true
        var count = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    /// Lets in one piece of work. False after the seal.
    func acquire() -> Bool {
        state.withLock { state in
            guard state.isOpen else { return false }
            state.count += 1
            return true
        }
    }

    /// Ends one piece of work that `acquire()` let in.
    func release() {
        let waiters = state.withLock { state in
            state.count -= 1
            guard state.count == 0 else { return [CheckedContinuation<Void, Never>]() }
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func seal() { state.withLock { $0.isOpen = false } }

    /// Returns when no work that the gate let in runs.
    func waitUntilDrained() async {
        await withCheckedContinuation { continuation in
            let finished = state.withLock { state in
                guard state.count != 0 else { return true }
                state.waiters.append(continuation)
                return false
            }
            if finished { continuation.resume() }
        }
    }
}
