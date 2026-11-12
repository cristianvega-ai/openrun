import AgentConversation
import AgentThreads
import CodexAgent
import DataStorage
import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

/// A Codex thread in the session process, with the fake app-server in
/// place of Codex, so no test spends the subscription of the owner.
@Suite struct CodexThreadTests {
    /// The recorded exchanges that the fake app-server plays, in order.
    ///
    /// - Parameter restart: The exchanges of a later start of the
    ///   app-server, with the file that marks the first start.
    private func servers(_ scripts: [String], restart: (scripts: [String], mark: String)? = nil) -> @Sendable () async throws -> CodexAccountServers {
        let fixtures = URL(fileURLWithPath: "../CodexAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
        func paths(_ names: [String]) -> String { names.map { fixtures.appending(path: $0 + ".jsonl").path }.joined(separator: ":") }
        var environment = ["PATH": "/usr/bin:/bin", "FAKE_CODEX_SCRIPTS": paths(scripts)]
        if let restart { (environment["FAKE_CODEX_RESTART_SCRIPTS"], environment["FAKE_CODEX_RESTART_MARK"]) = (paths(restart.scripts), restart.mark) }
        let launch = CodexServerLaunch(
            executablePath: RunningSessionProcess.productsDirectory.appendingPathComponent("fake-codex").path,
            environment: environment, folder: NSTemporaryDirectory())
        let pool = CodexAccountServers(launch: launch)
        return { pool }
    }

    /// The recorded thread of the fixtures works in this folder.
    private let record = ThreadRecord(agent: .codex, folder: "/work/project", model: CodexThreadRunner.configuredModel, permissionMode: "workspaceWrite")

    @Test func aMessageStartsAThreadOfCodexAndRunsATurn() async throws {
        let runner = CodexThreadRunner(record: record, servers: servers(["handshake", "thread-start", "plain-turn"]))
        let client = ThreadDeliveries()
        await runner.attach(ObjectIdentifier(client), listener: client.listener)
        #expect(client.hasEarlierEvents == false)
        try await runner.send(text: "Reply with the single word ok.")
        #expect(await eventually { await runner.facts.state == .finishedTurn })
        let facts = await runner.facts
        // Codex gave the identifier of its thread, which a resume needs, and a usage reading of the account.
        #expect(facts.record.hasConversation && facts.record.conversationIdentifier != record.conversationIdentifier)
        #expect(facts.record.title == "Reply with the single word ok." && facts.usage != nil && facts.usageReadAt != nil && !facts.isOpen)
        let texts = await runner.transcript.items.compactMap { if case .agentMessage(let message) = $0.content { message.text } else { nil } }
        let kept = await runner.buffer.entries.count
        #expect(texts == ["ok"] && client.events.count == kept)
        await runner.close()
        #expect(client.isClosed)
    }

    @Test func theAnswerOfTheUserAcceptsACommandOfCodex() async throws {
        let runner = CodexThreadRunner(record: record, servers: servers(["handshake", "thread-start", "command-accepted"]))
        try await runner.send(text: "Run the command.")
        #expect(await eventually { await runner.facts.state == .needsUser })
        let request = try #require(await runner.transcript.items.lazy.compactMap { item -> String? in
            if case .permissionRequest(let request) = item.content, request.isWaiting { return request.request.identifier }
            return nil
        }.first)
        #expect(await runner.answerPermission(request, allows: true, message: nil))
        #expect(await eventually { await runner.facts.state == .finishedTurn })
        // A request that does not wait takes no answer.
        #expect(await !runner.answerPermission(request, allows: true, message: nil))
        await runner.close()
    }

    @Test func twoCallersAtTheSameTimeOpenTheThreadOfCodexOnce() async throws {
        let runner = CodexThreadRunner(record: record, servers: servers(["handshake", "thread-start"]))
        async let first = runner.openThread(), second = runner.openThread()
        // The script has one start. A second start would get an empty answer and fail.
        let (one, other) = try await (first.identifier, second.identifier)
        #expect(one == other)
        await runner.close()
    }

    @Test func theEarlierTurnsOfACodexThreadComeFromCodexInPages() async throws {
        var kept = record
        kept.hasConversation = true
        let runner = CodexThreadRunner(record: kept, servers: servers(["handshake", "resume", "history"]))
        let newest = try await runner.historyPage(cursor: nil)
        #expect(!newest.events.isEmpty && newest.olderCursor != nil)
        let older = try await runner.historyPage(cursor: newest.olderCursor)
        #expect(!older.events.isEmpty && older.events != newest.events)
        // A thread with no turn has no history, and it opens no app-server for the question.
        let new = CodexThreadRunner(record: record, servers: { throw ThreadRunnerError.threadIsClosed })
        #expect(try await new.historyPage(cursor: nil) == CodexHistoryPage(events: [], olderCursor: nil))
        await runner.close()
    }

    @Test func aCodexThreadLeavesTheAppServerForATerminalAndTakesTheTurnsOfTheTerminal() async throws {
        // The app-server of the account ends when its last thread leaves, and a new one starts for the resume.
        let mark = NSTemporaryDirectory() + "fake-codex-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: mark) }
        let scripts = ["handshake", "thread-start", "plain-turn", "unsubscribe"]
        let runner = CodexThreadRunner(record: record, servers: servers(scripts, restart: (["handshake", "resume", "history"], mark)))
        try await runner.send(text: "Reply with the single word ok.")
        #expect(await eventually { await runner.facts.state == .finishedTurn })
        let arguments = await runner.terminalArguments
        #expect(arguments == ["resume", "00000000-0000-7000-8000-000000000001", "--sandbox", "workspace-write"])
        // Codex in the terminal has the thread now, so the chat sends nothing.
        await runner.leaveForTerminal()
        await #expect(throws: ThreadRequestError.openInTerminal) { try await runner.send(text: "More") }
        let before = await runner.transcript.items.count
        await runner.returnedFromTerminal()
        // The history holds turns after the turn of the chat. They come after it, and the thread takes messages again.
        let (after, inTerminal) = await (runner.transcript.items.count, runner.isInTerminal)
        #expect(after > before && !inTerminal)
        await runner.close()
    }

    @Test func aTurnOfCodexReachesTheListsAndItsAppServerCountsAsAnAgent() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The file holds a Codex thread in the folder of the recorded exchanges.
        let store = ThreadStore(dataFolder: DataFolder(path: folder.path))
        var list = ThreadList()
        try list.add(record)
        try store.save(list)
        let fixtures = URL(fileURLWithPath: "../CodexAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
        let scripts = ["handshake", "thread-start", "plain-turn"].map { fixtures.appending(path: $0 + ".jsonl").path }.joined(separator: ":")
        var settings = FakeAgentSettings.make(environment: ["FAKE_CODEX_SCRIPTS": scripts])
        settings.codexProgram = RunningSessionProcess.productsDirectory.appendingPathComponent("fake-codex").path
        let registry = ThreadRegistry(store: store) { [settings] in settings }
        #expect(await !registry.isStartedByAgent(getpid()))

        _ = try await registry.running(for: record.identifier).send(text: "Reply with the single word ok.", images: [])
        #expect(await eventually { await registry.summary(record.identifier)?.state == "finishedTurn" })
        let summary = try #require(await registry.summary(record.identifier))
        #expect(summary.agent == "codex" && !summary.isProcessRunning && summary.usageWindows != nil && summary.title == "Reply with the single word ok.")
        #expect(try store.load().list.thread(record.identifier)?.hasConversation == true)
        // A command of Codex is a child of the app-server, so the app-server counts as an agent of a thread.
        let servers = try #require(await registry.codexServers?.processIdentifiers())
        #expect(servers.count == 1)
        let (isAgent, isTest) = await (registry.isStartedByAgent(servers[0]), registry.isStartedByAgent(getpid()))
        #expect(isAgent && !isTest)
        await registry.terminateAll()
    }

    @Test func theRegistryKeepsACodexThreadWithItsOwnChoices() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let registry = ThreadRegistry(store: ThreadStore(dataFolder: DataFolder(path: folder.path))) { FakeAgentSettings.make() }
        let thread = try await registry.create(agent: "codex", folder: folder.path, model: nil, permissionMode: nil, name: "Notes")
        #expect(thread.agent == "codex" && thread.model == "default" && thread.permissionMode == "workspaceWrite")
        #expect(thread.models == ["default"] && thread.permissionModes == ["readOnly", "workspaceWrite"])
        try await registry.change(thread.identifier, model: "gpt-5.2-codex", permissionMode: "readOnly")
        let changed = try #require(await registry.summary(thread.identifier))
        #expect(changed.model == "gpt-5.2-codex" && changed.permissionMode == "readOnly" && changed.models == ["default", "gpt-5.2-codex"])
        // The modes of Claude Code are no sandbox of Codex, and only a thread with Claude Code has a process of its own and a hook.
        await #expect(throws: ThreadRequestError.self) { try await registry.change(thread.identifier, model: nil, permissionMode: "plan") }
        await #expect(throws: ThreadRequestError.onlyForClaudeCode) { try await registry.runner(for: thread.identifier) }
        #expect(try await registry.running(for: thread.identifier) is CodexThreadRunner)
        #expect(try await registry.codexHistoryPage(of: thread.identifier, cursor: nil).events.isEmpty)
        try await registry.close(thread.identifier)
        #expect(await registry.allSummaries.isEmpty)
    }
}
