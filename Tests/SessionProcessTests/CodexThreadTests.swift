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
    private func servers(_ scripts: [String]) -> @Sendable () async throws -> CodexAccountServers {
        let fixtures = URL(fileURLWithPath: "../CodexAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
        let paths = scripts.map { fixtures.appending(path: $0 + ".jsonl").path }.joined(separator: ":")
        let launch = CodexServerLaunch(
            executablePath: RunningSessionProcess.productsDirectory.appendingPathComponent("fake-codex").path,
            environment: ["PATH": "/usr/bin:/bin", "FAKE_CODEX_SCRIPTS": paths], folder: NSTemporaryDirectory())
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
}
