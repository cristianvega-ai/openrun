import AgentConversation
import AppKit
import ChatView
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Synchronization
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

    @Test func overviewRecoveryBeforeOldCloseReconnectsTheChat() async throws {
        let process = try FakeAgentProcess.start()
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        pane.attach()
        pane.take([.closed])
        #expect(await waitUntil { pane.attachment != nil && pane.isReplayComplete })
    }

    @Test func aThreadThatEndedDoesNotReconnect() async throws {
        let process = try FakeAgentProcess.start()
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        pane.attach()
        pane.take([.threadEnded])
        #expect(pane.attachment == nil && !pane.isAttaching && !pane.shouldReconnectAfterAttach)
    }

    @Test func aStateOnlyEventUpdatesTheChat() async throws {
        let process = try FakeAgentProcess.start()
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        pane.take([.event(ConversationEvent(.turnEnded(TurnEnd(outcome: .done))))])
        #expect(pane.chat.transcript == pane.transcript)
    }

    @Test func reconnectDropsAnObsoleteHistoryPage() async throws {
        let process = try FakeAgentProcess.start()
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        let oldGeneration = pane.historyGeneration
        pane.historyCursor = 42
        pane.historyToken = "old"
        pane.disconnected()
        pane.attach()
        #expect(pane.historyCursor == nil && pane.historyToken == nil)
        pane.tookHistory(.success((events: [], before: 99, cursor: "stale")), generation: oldGeneration)
        #expect(pane.historyCursor == nil && pane.historyToken == nil)
    }

    @Test func messageDoesNotWaitForOtherPaneWork() async throws {
        let process = try FakeAgentProcess.start()
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        let gate = DispatchSemaphore(value: 0)
        let entered = Mutex(false)
        pane.work.async { entered.withLock { $0 = true }; gate.wait() }
        defer { gate.signal() }
        #expect(await waitUntil { entered.withLock { $0 } })
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn })
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
        // The feed brings the usage reading of the turn, and a window at its limit makes the thread wait.
        var summary = try #require(try SessionClient(location: pane.socket).threads().first)
        #expect(summary.usageWindows != nil)
        pane.update(summary, home: process.directory.path)
        #expect(pane.chat.facts.usage?.contains("% used · read ") == true && pane.chat.facts.condition == .ready)
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        summary.usageWindows = [ThreadUsageWindow(name: "seven_day", usedFraction: 1, resetTime: reset, status: "rejected")]
        pane.update(summary, home: process.directory.path)
        #expect(pane.chat.facts.condition == .atLimit(resetTime: reset, otherAccounts: []))
        // The chat offers the other accounts of the agent, and a choice goes to the host.
        var chosen: [String] = []
        pane.continueOnAccount = { chosen.append($0) }
        pane.update(summary, home: process.directory.path, otherAccounts: [ChatAccount(identifier: "Work", name: "Work")])
        pane.chatViewController(pane.chat, startNewThreadOnAccount: "Work")
        #expect(pane.chat.facts.condition == .atLimit(resetTime: reset, otherAccounts: [ChatAccount(identifier: "Work", name: "Work")]) && chosen == ["Work"])
    }

    @Test func aTurnThatFailsForTheLoginTellsTheUserToSignIn() async throws {
        let process = try FakeAgentProcess.start(turns: ["authentication-failure", "plain-turn"])
        defer { process.stop() }
        let socket = try SocketLocation(path: process.socketPath)
        let thread = try SessionClient(location: socket).createThread(agent: "claude-code", folder: process.directory.path)
        let pane = ThreadPaneController(summary: thread, socket: socket, home: process.directory.path)
        pane.attach()
        defer { pane.close() }
        #expect(await waitUntil { pane.isReplayComplete })
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Hi"))
        #expect(await waitUntil { pane.chat.facts.condition == .notSignedIn(otherAccounts: []) })
        // The box offers the terminal, where the user signs in, and the other accounts of the settings.
        var opened = 0
        pane.openInTerminal = { opened += 1 }
        pane.chatViewControllerOpenInTerminal(pane.chat)
        let other = [ChatAccount(identifier: "Work", name: "Work")]
        pane.update(thread, home: process.directory.path, otherAccounts: other)
        #expect(opened == 1 && pane.chat.facts.condition == .notSignedIn(otherAccounts: other))
        // The next turn works, and the advice goes away.
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn && pane.chat.facts.condition == .ready })
    }

    @Test func theChatTakesTheEarlierTurnsFromTheHistoryOfTheAgent() async throws {
        let settings = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: settings) }
        let process = try FakeAgentProcess.start(environment: ["CLAUDE_CONFIG_DIR": settings.path])
        defer { process.stop() }
        let pane = try await attach(to: process)
        defer { pane.close() }
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn })
        let live = pane.transcript.items.map(\.identifier)

        // The history of Claude Code holds one earlier turn of this conversation.
        let folder = settings.appending(path: "projects/" + pane.chat.facts.threadIdentifier)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: FakeAgentProcess.fixtures.appending(path: "history.jsonl"), to: folder.appending(path: pane.chat.facts.threadIdentifier + ".jsonl"))
        pane.chat.facts.hasEarlierHistory = true
        pane.chatViewControllerLoadEarlierHistory(pane.chat)
        #expect(pane.chat.facts.isLoadingEarlierHistory)
        #expect(await waitUntil { !pane.chat.facts.isLoadingEarlierHistory })
        let items = pane.transcript.items.map(\.identifier)
        #expect(items.first == "user:00000000-0000-4000-8000-000000000195" && Array(items.suffix(live.count)) == live && items.count > live.count)
        // The start of the history came, so the chat offers no older turns.
        #expect(!pane.chat.facts.hasEarlierHistory && pane.chat.transcript == pane.transcript && pane.transcript.state == .finishedTurn)
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
