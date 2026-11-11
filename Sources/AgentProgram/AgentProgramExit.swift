import Darwin
import PseudoTerminal

/// The signals and the end of an agent program.
extension AgentProgram {
    /// Sends `signal` to the program and to every process of its group,
    /// such as SIGINT to stop a turn. Nothing happens after the program
    /// was reaped, because its number can then belong to another program.
    public func send(signal: Int32) {
        queue.sync { reaper?.signalGroup(signal) }
    }

    /// Ends the program and its group: SIGTERM, and SIGKILL after
    /// `gracePeriod`. Returns after the program was reaped.
    public func terminate(gracePeriod: Duration = .seconds(1)) async {
        send(signal: SIGTERM)
        send(signal: SIGCONT)
        let deadline = ContinuousClock.now + gracePeriod
        while !hasExited, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        send(signal: SIGKILL)
        _ = await waitForExit()
    }

    var hasExited: Bool {
        queue.sync { exit != nil }
    }

    /// Closes the pipes and ends the waits, after the reap.
    func programEnded(_ reason: ProgramExit) {
        for descriptor in [outputDescriptor, errorDescriptor, inputDescriptor] { close(descriptor) }
        exit = reason
        for waiter in exitWaiters { waiter.resume(returning: reason) }
        exitWaiters.removeAll()
    }
}
