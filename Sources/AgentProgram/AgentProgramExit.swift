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

    /// Ends the output and the waits, after the reap.
    func programEnded(_ reason: ProgramExit) {
        // Output that the program wrote before it ended can still wait in
        // the pipe. It comes before the stream finishes.
        readOutput(honoringBackpressure: false)
        readStandardError()
        outputContinuation.finish()
        exit = reason
        close(inputDescriptor)
        if outputSourceIsSuspended {
            outputSource?.resume()
            outputSourceIsSuspended = false
        }
        outputSource?.cancel()
        errorSource?.cancel()
        for waiter in exitWaiters { waiter.resume(returning: reason) }
        exitWaiters.removeAll()
    }
}
