import AgentProgram
import Darwin
import Foundation
import PseudoTerminal
import Testing

/// Signals reach the program and every process that it started, and none
/// of them stays behind.
@Suite struct AgentProgramGroupTests {
    /// A shell that starts a shell that starts `sleep`, and prints the
    /// number of `sleep`. Background jobs of a shell ignore SIGINT, so only
    /// the end of the group can stop that `sleep`.
    func startFamily() async throws -> (AgentProgram, pid_t) {
        let program = try startProgram("sh", ["-c", "sh -c 'sleep 300 & echo $!; wait' & wait"])
        var text = ""
        for await chunk in program.output {
            program.markOutputConsumed(chunk.count)
            text += String(decoding: chunk, as: UTF8.self)
            if text.hasSuffix("\n") { break }
        }
        let grandchild = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(!isGone(grandchild))
        return (program, grandchild)
    }

    @Test(arguments: [SIGINT, SIGTERM, SIGKILL])
    func aSignalEndsTheProgramAndTheProcessesThatItStarted(signal: Int32) async throws {
        let (program, grandchild) = try await startFamily()
        program.send(signal: signal)
        let exit = await program.waitForExit()
        if signal != SIGINT { #expect(exit == .signaled(signal: signal)) }
        #expect(isGone(grandchild))
        // A signal after the reap reaches nothing.
        program.send(signal: SIGKILL)
    }

    @Test func aProgramThatEndsByItselfTakesTheRestOfItsGroupAlong() async throws {
        let program = try startProgram("sh", ["-c", "sleep 300 & echo $!"])
        let grandchild = try #require(pid_t(String(decoding: await readAll(program), as: UTF8.self).trimmingCharacters(in: .newlines)))
        #expect(await program.waitForExit() == .exited(status: 0))
        #expect(isGone(grandchild))
    }

    @Test func terminateEndsAProgramThatIgnoresSIGTERM() async throws {
        let program = try startProgram("sh", ["-c", "trap '' TERM; echo ready; while :; do sleep 1; done"])
        for await _ in program.output { break }
        let start = ContinuousClock.now
        await program.terminate(gracePeriod: .milliseconds(200))
        #expect(await program.waitForExit() == .signaled(signal: SIGKILL))
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
