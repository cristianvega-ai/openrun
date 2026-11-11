import AgentConversation
import AppKit
import ChatView
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import SessionsList
import Testing
@testable import OpenRunApplication

/// The agent threads in the main window, with the fake agent in place of Claude Code.
@MainActor @Suite(.serialized) struct WorkspaceThreadTests {
    private func start(turns: [String] = ["plain-turn"], mode: String = "replay", isApplication: Bool = false) async throws -> TestWorkspace {
        let test = try TestWorkspace(process: FakeAgentProcess.start(turns: turns, mode: mode, isApplication: isApplication))
        test.workspace.start()
        #expect(await waitUntil { test.workspace.connection.hasThreadList })
        return test
    }

    private func row(_ test: TestWorkspace, _ identifier: UUID) -> SessionRowDisplay? {
        test.workspace.window.sessionsList.content.rows.first { $0.identifier == identifier }
    }

    @Test func aNewThreadShowsItsChatAndAMessageRunsATurn() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        #expect(workspace.window.sessionsList.content.agents == ["Claude Code"])
        workspace.sessionsList(workspace.window.sessionsList, didRequest: .thread(agent: "Claude Code"))
        #expect(await waitUntil { workspace.shownThread != nil && workspace.threadPanes.existing(workspace.shownThread!)?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread)
        let pane = try #require(workspace.threadPanes.existing(thread))
        #expect(workspace.layout.selectedRow == thread && row(test, thread)?.kind == .agentThread(agent: "Claude Code", model: "Opus", account: nil))
        #expect(row(test, thread)?.title == "New Thread" && pane.chat.view.window === workspace.window.window)

        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn && row(test, thread)?.title == "Reply with the single word ok." })
        workspace.sessionsList(workspace.window.sessionsList, didRename: thread, to: "Notes")
        #expect(await waitUntil { row(test, thread)?.title == "Notes" && pane.chat.facts.title == "Notes" })
    }

    @Test func aCloseOfAThreadAsksFirstAndThenRemovesItsRow() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        var questions: [String] = [], agrees = false
        workspace.confirmCloseOfThread = { title, answer in
            questions.append(title)
            answer(agrees)
        }
        workspace.newThread()
        #expect(await waitUntil { workspace.shownThread != nil })
        let thread = try #require(workspace.shownThread)
        workspace.closeRow(thread)
        try await Task.sleep(for: .milliseconds(200))
        #expect(questions == ["New Thread"] && test.shownRows == [thread])
        agrees = true
        workspace.closeRow(thread)
        #expect(await waitUntil { test.shownRows.isEmpty && workspace.shown == .nothing })
        #expect(workspace.threadPanes.all.isEmpty && workspace.layout.selectedRow == nil)
    }

    @Test func anAgentThatWaitsForAnAnswerNotifiesUnlessItsChatIsInView() async throws {
        let test = try await start(turns: ["command-turn"], mode: "askPermission", isApplication: true)
        defer { test.stop() }
        let workspace = test.workspace
        let socket = workspace.socket
        let thread = try SessionClient(location: socket).createThread(agent: "claude-code", folder: test.process.directory.path, name: "Build")
        #expect(await waitUntil { row(test, thread.identifier) != nil })
        _ = try SessionClient(location: socket).sendThreadMessage(thread.identifier, text: "Create the file.")
        #expect(await waitUntil { row(test, thread.identifier)?.alert == "Waits for your answer" })
        #expect(test.notifier.posted.map(\.title) == ["Build"] && test.notifier.posted.first?.body == "Claude Code waits for your answer.")
        #expect(workspace.window.projectsList.content.needsYouCount == 1)

        // The user opens the notification and allows the call in the chat.
        test.notifier.opened?(thread.identifierText)
        #expect(await waitUntil { workspace.threadPanes.existing(thread.identifier)?.transcript.state == .needsUser })
        let pane = try #require(workspace.threadPanes.existing(thread.identifier))
        let request = try #require(pane.transcript.items.lazy.compactMap { item -> String? in
            if case .permissionRequest(let request) = item.content { return request.request.identifier }
            return nil
        }.first)
        pane.chatViewController(pane.chat, answerPermissionRequest: request, with: .allow)
        #expect(await waitUntil { row(test, thread.identifier)?.alert == nil && pane.transcript.state == .finishedTurn })
        #expect(test.notifier.removed == [thread.identifierText])
    }
}
