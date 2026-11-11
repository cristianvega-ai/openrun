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

/// Reads the output to its end, and marks each chunk as consumed.
func readAll(_ program: AgentProgram) async -> [UInt8] {
    var bytes: [UInt8] = []
    for await chunk in program.output {
        bytes += chunk
        program.markOutputConsumed(chunk.count)
    }
    return bytes
}

/// Whether the process ended. A zombie counts as ended: its parent ended
/// too, and launchd reaps it soon.
func isGone(_ processIdentifier: pid_t) -> Bool {
    !runs(processIdentifier)
}

/// Whether the process runs, and is not a zombie.
func runs(_ processIdentifier: pid_t) -> Bool {
    var information = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &information, size) == size
        && information.pbi_status != UInt32(SZOMB)
}

@Suite struct AgentProgramTests {
    @Test func aProgramTakesInputAndGivesOutputAndItsStatus() async throws {
        let program = try startProgram("cat")
        try await program.write(Array("hello\n".utf8))
        try await program.write([])
        program.closeInput()
        #expect(String(decoding: await readAll(program), as: UTF8.self) == "hello\n")
        #expect(await program.waitForExit() == .exited(status: 0))
        // The program was reaped: no zombie is left.
        #expect(waitpid(program.processIdentifier, nil, WNOHANG) == -1)
        await #expect(throws: AgentProgramError.programEnded) { try await program.write([1]) }
    }

    @Test func theStatusAndTheSignalOfTheEndCome() async throws {
        let program = try startProgram("sh", ["-c", "exit 3"])
        #expect(await program.waitForExit() == .exited(status: 3))
        // The program was reaped: no zombie is left, and a signal reaches nothing.
        #expect(waitpid(program.processIdentifier, nil, WNOHANG) == -1)
        program.send(signal: SIGKILL)
        #expect(await (try startProgram("sh", ["-c", "kill -USR1 $$"])).waitForExit() == .signaled(signal: SIGUSR1))
    }

    @Test func theOutputComesWholeAndThenTheEnd() async throws {
        let program = try startProgram("sh", ["-c", "echo hello; echo world"])
        #expect(String(decoding: await readAll(program), as: UTF8.self) == "hello\nworld\n")
        #expect(await program.waitForExit() == .exited(status: 0))
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

    @Test func standardErrorKeepsItsNewestBytes() async throws {
        let program = try startProgram("sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' a >&2; echo end >&2"])
        _ = await readAll(program)
        _ = await program.waitForExit()
        let text = program.standardErrorText
        #expect(text.utf8.count == AgentProgram.standardErrorLimit)
        #expect(text.hasSuffix("aaa\nend\n") || text.hasSuffix("aaaend\n"))
    }
}
