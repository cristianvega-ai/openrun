import AccountUsage
import AgentConversation
import AppKit
import DataStorage
import PseudoTerminal
@testable import ChatView
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
        #expect(workspace.window.sessionsList.content.agents == ["Claude Code", "Codex"])
        workspace.sessionsList(workspace.window.sessionsList, didRequest: .thread(agent: "Claude Code"))
        #expect(await waitUntil { workspace.shownThread != nil && workspace.threadPanes.existing(workspace.shownThread!)?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread)
        let pane = try #require(workspace.threadPanes.existing(thread))
        #expect(workspace.layout.selectedRow == thread && row(test, thread)?.kind == .agentThread(agent: "Claude Code", model: "Opus", account: nil))
        #expect(row(test, thread)?.title == "New Thread" && pane.chat.view.window === workspace.window.window)
        // The item of Command-W names what it closes.
        let close = NSMenuItem(title: "", action: #selector(Workspace.closeSession(_:)), keyEquivalent: "")
        #expect(workspace.validateMenuItem(close) && close.title == "Close Thread")

        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn && row(test, thread)?.title == "Reply with the single word ok." })
        workspace.sessionsList(workspace.window.sessionsList, didRename: thread, to: "Notes")
        #expect(await waitUntil { row(test, thread)?.title == "Notes" && pane.chat.facts.title == "Notes" })
    }

    @Test func theButtonForANewThreadOffersEachAccountOfTheSettings() async throws {
        let test = try await start(isApplication: true)
        defer { test.stop() }
        let workspace = test.workspace
        let accounts = #"[{"folder":"\#(test.process.directory.path)","name":"Work"}]"#
        try SessionClient(location: workspace.socket).changeSetting(named: "claude-code-accounts", to: accounts)
        #expect(await waitUntil { workspace.window.sessionsList.content.accounts == ["Claude Code": ["Work"], "Codex": []] })
        workspace.sessionsList(workspace.window.sessionsList, didRequest: .thread(agent: "Claude Code", account: "Work"))
        #expect(await waitUntil { workspace.shownThread.flatMap { row(test, $0) }?.kind == .agentThread(agent: "Claude Code", model: "Opus", account: "Work") })
        #expect(workspace.threadPanes.existing(try #require(workspace.shownThread))?.chat.facts.accountName == "Work")
        // File > New Thread uses the account that the user chose last, while the settings hold it.
        let first = try #require(workspace.shownThread)
        workspace.newThread(nil)
        #expect(await waitUntil { workspace.shownThread != first && workspace.shownThread.flatMap { row(test, $0) }?.kind == .agentThread(agent: "Claude Code", model: "Opus", account: "Work") })
        try SessionClient(location: workspace.socket).changeSetting(named: "claude-code-accounts", to: "[]")
        #expect(await waitUntil { workspace.settings.claudeCodeAccounts.isEmpty } && workspace.lastAccount(of: "claude-code") == nil)
    }

    @Test func aThreadGoesOnInANewThreadUnderAnotherAccountWithItsWordsAsTheDraft() async throws {
        let test = try await start(isApplication: true)
        defer { test.stop() }
        let workspace = test.workspace
        let accounts = #"[{"folder":"\#(test.process.directory.path)","name":"Work"}]"#
        try SessionClient(location: workspace.socket).changeSetting(named: "claude-code-accounts", to: accounts)
        workspace.newThread()
        #expect(await waitUntil { workspace.shownThread.flatMap { workspace.threadPanes.existing($0) }?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread), pane = try #require(workspace.threadPanes.existing(thread))
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { pane.transcript.state == .finishedTurn && !workspace.settings.claudeCodeAccounts.isEmpty })
        let earlier = try #require(workspace.connection.overview.thread(thread))
        #expect(workspace.otherAccounts(of: earlier) == [ChatAccount(identifier: "Work", name: "Work")])
        pane.chatViewController(pane.chat, startNewThreadOnAccount: "Work")
        #expect(await waitUntil { workspace.shownThread != thread && workspace.shownThread.flatMap { workspace.threadPanes.existing($0) } != nil })
        let new = try #require(workspace.shownThread.flatMap { workspace.connection.overview.thread($0) })
        #expect(new.accountName == "Work" && new.folder == earlier.folder && new.model == earlier.model)
        #expect(workspace.otherAccounts(of: new).map(\.name) == ["the Account of Your Shell"])
        let draft = try #require(workspace.threadPanes.existing(new.identifier)).chat.composer.draft.text
        #expect(draft.hasPrefix("Go on with the work of this earlier conversation.") && draft.hasSuffix("User:\nReply with the single word ok.\n\nAgent:\nok"))
    }

    @Test func theButtonForANewThreadOffersCodexWithItsOwnChoices() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.sessionsList(workspace.window.sessionsList, didRequest: .thread(agent: "Codex"))
        #expect(await waitUntil { workspace.shownThread.flatMap { workspace.threadPanes.existing($0) }?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread), pane = try #require(workspace.threadPanes.existing(thread))
        #expect(row(test, thread)?.kind == .agentThread(agent: "Codex", model: "Codex", account: nil) && pane.chat.facts.agentName == "Codex")
        #expect(pane.chat.facts.model?.title == "Default Model" && pane.chat.facts.permissionModes.map(\.title) == ["Read Only", "Write in Folder"])
    }

    @Test func theMenusOfTheChatChangeTheModelAndTheModeOfTheThread() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        var failures: [String] = []
        workspace.showFailure = { failures.append($1) }
        workspace.newThread()
        #expect(await waitUntil { workspace.shownThread.flatMap { workspace.threadPanes.existing($0) }?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread), pane = try #require(workspace.threadPanes.existing(thread))
        #expect(pane.chat.facts.models.map(\.title) == ["Fable", "Opus", "Sonnet", "Haiku"] && pane.chat.facts.model?.title == "Opus")
        #expect(pane.chat.facts.permissionModes.map(\.title) == ["Plan Only", "Rules Only", "Ask First"] && pane.chat.facts.permissionMode?.title == "Ask First")

        pane.chatViewController(pane.chat, selectModel: "sonnet")
        pane.chatViewController(pane.chat, selectPermissionMode: "plan")
        #expect(await waitUntil { pane.chat.facts.model?.identifier == "sonnet" && pane.chat.facts.permissionMode?.identifier == "plan" })
        #expect(row(test, thread)?.kind == .agentThread(agent: "Claude Code", model: "Sonnet", account: nil) && failures.isEmpty)
        // Only the settings window gives a wider mode than the one of the settings.
        pane.chatViewController(pane.chat, selectPermissionMode: "auto")
        #expect(await waitUntil { failures.count == 1 })
        #expect(failures.first?.contains("A thread can take these permission modes: plan, dontAsk, default.") == true)
        #expect(pane.chat.facts.permissionMode?.identifier == "plan")
    }

    @Test func openInTerminalShowsTheTerminalInTheRowOfTheThreadAndBackToChatReturns() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.newThread()
        #expect(await waitUntil { workspace.shownThread.flatMap { workspace.threadPanes.existing($0) }?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread), pane = try #require(workspace.threadPanes.existing(thread))
        #expect(workspace.window.shownContent?.topRowItems.count == 2)

        pane.chatViewControllerOpenInTerminal(pane.chat)
        #expect(await waitUntil { workspace.shownSession != nil })
        let terminal = try #require(workspace.shownSession)
        // The terminal shows in the row of the thread, and it has no row of its own.
        #expect(workspace.connection.overview.thread(thread)?.terminalSession == terminal && test.shownRows == [thread])
        #expect(pane.chat.facts.condition == .openInTerminal && workspace.layout.selectedRow == thread)
        let back = try #require(workspace.window.shownContent?.topRowItems.first as? BackToChatButton)
        workspace.backToChat(back)
        #expect(await waitUntil { workspace.shownThread == thread && pane.chat.facts.condition == .ready })
        #expect(workspace.connection.overview.sessions.isEmpty && test.shownRows == [thread])
    }

    @Test func inARowWithSplitsTheTerminalOfAConversationTakesThePlaceOfItsChat() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.loginShell = LoginShell(path: "/bin/sh")
        workspace.newThread()
        #expect(await waitUntil { workspace.shownThread.flatMap { workspace.threadPanes.existing($0) }?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread), chat = try #require(workspace.threadPanes.existing(thread)).chat
        workspace.splitRight(nil)
        #expect(await waitUntil { workspace.splitView != nil && workspace.focusedLeaf != thread })
        workspace.selectNextPane(nil)
        func item(_ action: Selector) -> NSMenuItem { NSMenuItem(title: "", action: action, keyEquivalent: "") }
        let (open, back) = (item(#selector(Workspace.openFocusedThreadInTerminal(_:))), item(#selector(Workspace.returnFocusedThreadToChat(_:))))
        #expect(workspace.focusedLeaf == thread && workspace.validateMenuItem(open) && !workspace.validateMenuItem(back))
        // Next Pane gave the keyboard to the message field of the chat.
        #expect(workspace.window.window.firstResponder === chat.focusView)
        // A row with splits has no top row for the button, so the menu opens the terminal.
        workspace.openFocusedThreadInTerminal(nil)
        #expect(await waitUntil {
            guard let terminal = workspace.connection.overview.thread(thread)?.terminalSession else { return false }
            return workspace.splitView?.view(of: thread) === workspace.panes.existing(terminal)?.content.view
        })
        // Under load the focus can come a moment after the view of the terminal.
        #expect(await waitUntil { test.shownRows == [thread] && workspace.focusedLeaf == thread && workspace.validateMenuItem(back) && !workspace.validateMenuItem(open) })
        workspace.returnFocusedThreadToChat(nil)
        #expect(await waitUntil { workspace.connection.overview.thread(thread)?.terminalSession == nil && workspace.splitView?.view(of: thread) === chat.view })
        // The focus comes back to the chat a moment after its view.
        #expect(await waitUntil { workspace.validateMenuItem(open) } && workspace.connection.overview.sessions.count == 1)
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

    @Test func anAccountKeepsItsLastUsageReadingAfterItsThreadIsGone() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.confirmCloseOfThread = { _, answer in answer(true) }
        workspace.newThread()
        #expect(await waitUntil { workspace.shownThread.flatMap { workspace.threadPanes.existing($0) }?.isReplayComplete == true })
        let thread = try #require(workspace.shownThread), pane = try #require(workspace.threadPanes.existing(thread))
        pane.chatViewController(pane.chat, send: ChatOutgoingMessage(text: "Reply with the single word ok."))
        #expect(await waitUntil { workspace.window.projectsList.content.accounts.map(\.title) == ["Claude Code"] })
        workspace.closeRow(thread)
        #expect(await waitUntil { test.shownRows.isEmpty && workspace.connection.overview.threads.isEmpty })
        #expect(workspace.window.projectsList.content.accounts.map(\.title) == ["Claude Code"])
        // The Accounts pane of the settings shows the same reading.
        workspace.showSettings(nil)
        defer { workspace.settingsWindow?.close() }
        #expect(workspace.settingsWindow?.usage.map(\.title) == ["Claude Code"])
        // The reading stays in the data folder for the next start of the app.
        workspace.usageStore.finishWrites()
        #expect(AccountUsageStore(dataFolder: DataFolder(path: workspace.socket.folder)).load() == workspace.keptUsage && workspace.keptUsage.count == 1)
    }

    @Test func signInRunsTheLoginOfTheAgentInATerminalUnderTheAccount() async throws {
        let test = try await start(isApplication: true)
        defer { test.stop() }
        let workspace = test.workspace, folder = test.process.directory.path
        (workspace.home, workspace.loginShell, workspace.sessionEnvironment) = (folder, LoginShell(path: "/bin/sh"), ["HOME": folder, "PATH": "/usr/bin:/bin"])
        // A stand-in for the agent, so the test never starts the real login.
        let program = folder + "/agent-login"
        try "#!/bin/sh\nexec sleep 30\n".write(toFile: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program)
        let client = try SessionClient(location: workspace.socket)
        try client.changeSetting(named: "claude-code-program", to: program)
        try client.changeSetting(named: "claude-code-accounts", to: #"[{"folder":"\#(folder)/.claude-work","name":"Work"}]"#)
        #expect(await waitUntil { workspace.settings.claudeCodeAccounts.count == 1 && workspace.settings.claudeCodeProgram == program })
        // An account that the settings do not hold starts nothing.
        workspace.signIn(agent: "claude-code", account: "Home")
        workspace.signIn(agent: "claude-code", account: "Work")
        #expect(await waitUntil { workspace.connection.overview.sessions.first?.name == "Sign In to Claude Code · Work" })
        let session = try #require(workspace.connection.overview.sessions.first)
        #expect(workspace.connection.overview.sessions.count == 1 && session.command.last == "exec env CLAUDE_CONFIG_DIR='\(folder)/.claude-work' '\(program)' auth login")
        #expect(await waitUntil { workspace.layout.row(showing: session.identifier)?.identifier == workspace.layout.selectedRow })
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
