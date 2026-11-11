import AgentProgram
import Darwin
import Foundation
import PseudoTerminal
import Testing

/// Runs a real program on pipes, in a folder of its own.
func startProgram(_ executable: String, _ arguments: [String] = [], folder: String = NSTemporaryDirectory()) throws -> AgentProgram {
    try AgentProgram(launching: AgentProgramLaunch(
        executablePath: executable, arguments: arguments, folder: folder, environment: ["PATH": "/usr/bin:/bin"]))
}

@Suite struct AgentProgramTests {
    @Test func theStatusAndTheSignalOfTheEndCome() async throws {
        let program = try startProgram("sh", ["-c", "exit 3"])
        #expect(await program.waitForExit() == .exited(status: 3))
        // The program was reaped: no zombie is left, and a signal reaches nothing.
        #expect(waitpid(program.processIdentifier, nil, WNOHANG) == -1)
        program.send(signal: SIGKILL)
        #expect(await (try startProgram("sh", ["-c", "kill -USR1 $$"])).waitForExit() == .signaled(signal: SIGUSR1))
    }

    @Test func terminateEndsTheProgram() async throws {
        let program = try startProgram("sleep", ["300"])
        await program.terminate()
        #expect(await program.waitForExit() == .signaled(signal: SIGTERM))
    }

    @Test func aWrongLaunchIsRefusedBeforeAnythingStarts() throws {
        #expect(throws: AgentProgramError.programNotFound(name: "no-such-program-here")) { try startProgram("no-such-program-here") }
        #expect(throws: AgentProgramError.systemCallFailed(function: "chdir", code: ENOENT)) {
            try startProgram("cat", folder: "/no/such/folder")
        }
        #expect(throws: AgentProgramError.invalidLaunchValue(problem: "argument 1 holds a NUL character")) { try startProgram("cat", ["a\u{0}b"]) }
        #expect(throws: AgentProgramError.invalidLaunchValue(problem: "an environment variable name holds an equals sign (=)")) {
            try AgentProgram(launching: AgentProgramLaunch(executablePath: "/bin/cat", folder: "/", environment: ["A=B": "c"]))
        }
    }
}
