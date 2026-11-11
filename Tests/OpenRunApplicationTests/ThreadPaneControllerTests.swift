import AgentConversation
import AppKit
import ChatView
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct ThreadPaneControllerTests {
    /// A pane that is attached to a new thread of the session process.
    private func attach(to process: RunningSessionProcess) async throws -> ThreadPaneController {
        _ = NSApplication.shared
        let socket = try SocketLocation(path: process.socketPath)
        let thread = try SessionClient(location: socket).createThread(agent: "claude-code", folder: process.directory.path, name: "Notes")
        let pane = ThreadPaneController(summary: thread, socket: socket, home: process.directory.path)
        pane.attach()
        #expect(await waitUntil { pane.isReplayComplete && pane.attachment != nil })
        return pane
    }

    private func agentTexts(_ pane: ThreadPaneController) -> [String] {
        pane.transcript.items.compactMap { if case .agentMessage(let message) = $0.content { message.text } else { nil } }
    }

    @Test func theChatShowsATurnOfItsThread() async throws {
        let process = try FakeAgentProcess.start()
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        #expect(pane.chat.facts.title == "Notes" && pane.chat.facts.agentName == "Claude Code" && pane.chat.facts.model?.title == "Opus")
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn })
        #expect(agentTexts(pane) == ["ok"] && pane.chat.transcript == pane.transcript)
    }

    @Test func theAnswerInTheChatAllowsTheCallOfTheAgent() async throws {
        let process = try FakeAgentProcess.start(turns: ["command-turn"], mode: "askPermission", isApplication: true)
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        var failures: [String] = []
        pane.failed = { failures.append($0) }
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Create the file."))
        #expect(await waitUntil { pane.transcript.state == .needsUser })
        let request = try #require(pane.transcript.items.lazy.compactMap { item -> String? in
            if case .permissionRequest(let request) = item.content { return request.request.identifier }
            return nil
        }.first)
        pane.chatViewController(pane.chat, answerPermissionRequest: request, with: .allow)
        #expect(await waitUntil { pane.transcript.state == .finishedTurn })
        #expect(failures.isEmpty)
    }
}
