import Foundation
import PseudoTerminal
import SessionProtocol
import Testing
@testable import OpenRunApplication

@Suite struct NewSessionLaunchTests {
    @Test func anEmptyCommandLineStartsTheLoginShell() {
        let launch = NewSessionLaunch(commandLine: "", folder: "/work/app")
        #expect(launch.command == nil && launch.folder == "/work/app")
        let size = SessionSize(columns: 100, rows: 30)
        #expect(launch.request(size: size, environment: ["A": "b"]) == .createSession(folder: "/work/app", command: nil, size: size, environment: ["A": "b"]))
    }

    /// The agents live in folders that only the shell of the user adds to the `PATH`.
    @Test func aCommandRunsInThePlaceOfAnInteractiveLoginShell() {
        let launch = NewSessionLaunch(commandLine: "claude --model opus", folder: "/work", shell: LoginShell(path: "/bin/zsh"))
        #expect(launch.command == ["/bin/zsh", "-l", "-i", "-c", "exec claude --model opus"])
    }
}

@Suite struct CloseQuestionTests {
    private func session(foreground: String?, isInProgress: Bool? = nil) -> SessionSummary {
        var summary = SessionSummary(identifier: UUID(), folder: "/", command: ["/bin/zsh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date())
        (summary.foregroundProgram, summary.isInProgress) = (foreground, isInProgress)
        return summary
    }

    @Test func aShellAtItsPromptClosesWithNoQuestion() {
        #expect(CloseQuestion(session: session(foreground: "zsh", isInProgress: false)) == nil)
        #expect(CloseQuestion(session: session(foreground: "-bash")) == nil)
        #expect(CloseQuestion(session: session(foreground: nil)) == nil)
    }

    @Test func aProgramOrACommandInProgressAsksFirstAndTheFirstButtonKeepsIt() throws {
        let editor = try #require(CloseQuestion(session: session(foreground: "vim", isInProgress: false)))
        #expect(editor.program == "vim" && editor.message.hasPrefix("vim still runs in it."))
        #expect(editor.buttons == ["Cancel", "Close Session"])
        #expect(CloseQuestion(session: session(foreground: "zsh", isInProgress: true))?.program == "A command")
        #expect(CloseQuestion(session: session(foreground: nil, isInProgress: true))?.program == "A command")
        #expect(CloseQuestion(session: session(foreground: "claude"))?.program == "claude")
    }
}
