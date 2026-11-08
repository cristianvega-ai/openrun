import Testing
@testable import PseudoTerminal

@Suite struct ForegroundProgramTests {
    @Test func namesTheShellAtItsPromptAndTheCommandThatRuns() async throws {
        let terminal = try PseudoTerminal(launching: ProgramLaunch(
            executablePath: "/bin/zsh",
            argumentZero: "-zsh",
            arguments: ["-f", "-i"],
            folder: "/",
            environment: ["PATH": "/usr/bin:/bin", "PS1": "ready> "],
            size: PseudoTerminalSize(columns: 80, rows: 24)
        ))
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ready> ", timeout: .seconds(10)))
        #expect(terminal.foregroundProgram == ForegroundProgram(name: "zsh", arguments: ["-zsh", "-f", "-i"]))

        // The system's sh is bash. The command keeps an empty argument.
        terminal.write(Array("/bin/sh -c 'sleep 30; true' ''\r".utf8))
        let command = ForegroundProgram(name: "bash", arguments: ["/bin/sh", "-c", "sleep 30; true", ""])
        #expect(await eventuallyTrue { terminal.foregroundProgram == command })
        await terminal.terminate()
    }

    @Test func hasNoProgramAfterTheProgramEnded() async throws {
        let terminal = try PseudoTerminal(launching: ProgramLaunch(
            executablePath: "/usr/bin/true", argumentZero: "true", arguments: [], folder: "/",
            environment: [:], size: PseudoTerminalSize(columns: 80, rows: 24)
        ))
        for await _ in terminal.output {}
        _ = await terminal.waitForExit()
        #expect(terminal.foregroundProgram == nil)
    }
}
