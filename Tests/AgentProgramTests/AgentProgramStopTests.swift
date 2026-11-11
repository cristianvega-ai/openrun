import AgentProgram
import Darwin
import Foundation
import PseudoTerminal
import Synchronization
import Testing

/// A program that stops, such as one that gets SIGTSTP, has not ended.
@Suite struct AgentProgramStopTests {
    /// Whether the process is stopped.
    static func isStopped(_ processIdentifier: pid_t) -> Bool {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &information, size) == size
            && information.pbi_status == UInt32(SSTOP)
    }

    @Test func terminateEndsAStoppedProgram() async throws {
        let program = try startProgram("sh", ["-c", "kill -STOP $$"])
        let deadline = ContinuousClock.now + .seconds(10)
        while !Self.isStopped(program.processIdentifier), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(Self.isStopped(program.processIdentifier))
        // A wait that never ends must not hang the test, so the test waits
        // for a flag with its own time limit.
        let finished = Mutex(false)
        let terminating = Task {
            await program.terminate(gracePeriod: .seconds(1))
            finished.withLock { $0 = true }
        }
        while !finished.withLock({ $0 }), ContinuousClock.now < deadline + .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard finished.withLock({ $0 }) else {
            Issue.record("terminate did not return")
            kill(program.processIdentifier, SIGKILL)
            return
        }
        await terminating.value
        #expect(await program.waitForExit() == .signaled(signal: SIGTERM))
    }
}
