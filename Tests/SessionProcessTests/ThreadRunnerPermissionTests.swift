import AgentConversation
import AgentThreads
import ClaudeCodeAgent
import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

/// A permission request waits for the user, and every other end refuses it.
@Suite struct ThreadRunnerPermissionTests {
    /// What the hook of the agent of this thread gets on its standard input.
    static func request(for record: ThreadRecord, conversation: String? = nil) throws -> ClaudeCodePermissionHookRequest {
        let identifier = conversation ?? record.conversationIdentifier
        let text = #"{"session_id":"\#(identifier)","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"touch x"}}"#
        return try ClaudeCodePermissionHookRequest(decoding: Data(text.utf8))
    }

    /// A runner with one request that waits, and the task that asked.
    private func ask(timeLimit: Duration = .seconds(60)) async throws -> (runner: ThreadRunner, asked: Task<ClaudeCodePermissionHookAnswer, Never>, identifier: String) {
        let record = FakeAgentSettings.record()
        let runner = ThreadRunner(record: record) { FakeAgentSettings.make() }
        let request = try Self.request(for: record)
        let asked = Task { await runner.askPermission(request, timeLimit: timeLimit) }
        #expect(await eventually { await !runner.waitingPermissions.isEmpty })
        return (runner, asked, try #require(await runner.waitingPermissions.keys.first))
    }

    private func ends(_ runner: ThreadRunner) async -> [PermissionEnd] {
        await runner.keptEvents.compactMap { if case .permissionEnded(let end) = $0.kind { end } else { nil } }
    }

    @Test func onlyTheAnswerOfTheUserAllowsACall() async throws {
        let (runner, asked, identifier) = try await ask()
        #expect(await runner.state == .needsUser)
        let shown = await runner.keptEvents.compactMap { if case .permissionRequested(let request) = $0.kind { request } else { nil } }
        #expect(shown.map(\.identifier) == [identifier] && shown.first?.toolName == "Bash")
        #expect(await runner.answerPermission(identifier, allows: true, message: nil))
        #expect(await asked.value == .allow)
        #expect(await ends(runner) == [PermissionEnd(identifier: identifier, outcome: .allowed)])
        // A second answer comes too late and changes nothing.
        #expect(await !runner.answerPermission(identifier, allows: false, message: nil))
        #expect(await ends(runner).count == 1)
    }

    @Test func aDenialCarriesTheMessageOfTheUserToTheAgent() async throws {
        let (runner, asked, identifier) = try await ask()
        #expect(await runner.answerPermission(identifier, allows: false, message: "Use the test folder."))
        #expect(await asked.value == .deny(message: "Use the test folder."))
        let (again, askedAgain, second) = try await ask()
        #expect(await again.answerPermission(second, allows: false, message: nil))
        #expect(await askedAgain.value == .deny(message: "The user denied this request."))
        _ = runner
    }

    @Test func aStopACloseTheTimeLimitAndAHookThatLeftRefuseTheRequest() async throws {
        let (stopped, askedStopped, first) = try await ask()
        await stopped.stop()
        #expect(await askedStopped.value == .deny(message: "The request ended before the user answered it."))
        #expect(await ends(stopped) == [PermissionEnd(identifier: first, outcome: .cancelled)])

        let (closed, askedClosed, _) = try await ask()
        await closed.close()
        #expect(await askedClosed.value == .deny(message: "The request ended before the user answered it."))

        let (late, askedLate, third) = try await ask(timeLimit: .milliseconds(50))
        #expect(await askedLate.value == .deny(message: "The user did not answer this request in time."))
        #expect(await ends(late) == [PermissionEnd(identifier: third, outcome: .timedOut)])

        let (left, askedLeft, fourth) = try await ask()
        askedLeft.cancel()
        #expect(await askedLeft.value == .deny(message: "The request ended before the user answered it."))
        #expect(await !left.answerPermission(fourth, allows: true, message: nil))
    }

    @Test func aRequestOfAnotherConversationIsRefusedAtOnce() async throws {
        let record = FakeAgentSettings.record()
        let runner = ThreadRunner(record: record) { FakeAgentSettings.make() }
        let answer = await runner.askPermission(try Self.request(for: record, conversation: UUID().uuidString.lowercased()))
        #expect(answer == .deny(message: "OpenRun could not ask the user for this request."))
        #expect(await runner.keptEvents.isEmpty)
    }
}
