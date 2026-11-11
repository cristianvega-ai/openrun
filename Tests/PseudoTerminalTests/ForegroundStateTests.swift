import Foundation
import Testing
@testable import PseudoTerminal

@Suite struct ForegroundStateTests {
    private func launch(_ program: String, _ arguments: [String], folder: String = "/") throws -> PseudoTerminal {
        try PseudoTerminal(launching: ProgramLaunch(
            executablePath: program, argumentZero: program, arguments: arguments, folder: folder,
            environment: ["PATH": "/usr/bin:/bin", "PS1": "ready> "], size: PseudoTerminalSize(columns: 80, rows: 24)
        ))
    }

    /// zsh reads each key of its line editor in raw mode. A command that it
    /// runs gets the terminal in line mode, and the folder of the shell.
    @Test func followsTheShellAndTheCommandThatItRuns() async throws {
        let terminal = try launch("/bin/zsh", ["-f", "-i"], folder: "/usr")
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ready> ", timeout: .seconds(10)))
        let atPrompt = try #require(terminal.foregroundState)
        #expect(atPrompt.program.name == "zsh" && atPrompt.leadsSession && !atPrompt.isInLineMode)
        #expect(atPrompt.currentFolder == "/usr")

        terminal.write(Array("cd /usr/bin && sleep 30\r".utf8))
        #expect(await eventuallyTrue { terminal.foregroundState?.program.name == "sleep" })
        let command = try #require(terminal.foregroundState)
        #expect(!command.leadsSession && command.isInLineMode && command.currentFolder == "/usr/bin")
        await terminal.terminate()
    }

    /// On macOS the controlling side of the pseudo terminal reads the mode
    /// that the program set on its side.
    @Test func readsTheModeThatTheProgramSets() async throws {
        let lineMode = try launch("/bin/sleep", ["30"])
        #expect(await eventuallyTrue { lineMode.foregroundState?.isInLineMode == true })
        await lineMode.terminate()
        let rawMode = try launch("/bin/sh", ["-c", "stty -icanon; exec sleep 30"])
        #expect(await eventuallyTrue { rawMode.foregroundState.map { $0.program.name == "sleep" && !$0.isInLineMode } == true })
        await rawMode.terminate()
    }

    @Test func hasNoStateAfterTheProgramEnded() async throws {
        let terminal = try launch("/usr/bin/true", [])
        for await _ in terminal.output {}
        _ = await terminal.waitForExit()
        #expect(terminal.foregroundState == nil)
    }
}
