import AgentConversation
import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing

/// A permission request from the hook of the fake agent to the answer of
/// the app, through a real session process and the real `openrun` tool.
@Suite struct ThreadPermissionTests {
    private final class Received: Sendable {
        let events = Mutex<[ThreadAttachment.Event]>([])
        func follow(_ attachment: ThreadAttachment) { attachment.startReceiving { [self] event in events.withLock { $0.append(event) } } }
        var conversation: [ConversationEvent] { events.withLock { $0 }.compactMap { if case .event(let event) = $0 { event } else { nil } } }
        var failures: [String] { events.withLock { $0 }.compactMap { if case .requestFailed(let failure) = $0 { failure.message } else { nil } } }
        var request: PermissionRequest? { conversation.lazy.compactMap { if case .permissionRequested(let request) = $0.kind { request } else { nil } }.first }
        var end: PermissionEnd? { conversation.lazy.compactMap { if case .permissionEnded(let end) = $0.kind { end } else { nil } }.first }
        /// What the fake agent says that its hook decided.
        var decision: String? {
            conversation.lazy.compactMap { event -> String? in
                guard case .unknown(let line) = event.kind, line.kind == "fake_hook" else { return nil }
                return line.text
            }.first
        }
    }

    /// A thread whose agent asks for a permission in its turn, with one attached client.
    /// - Parameter isApplication: Whether this test process counts as OpenRun.app.
    private func start(isApplication: Bool) throws -> (process: RunningSessionProcess, attachment: ThreadAttachment, received: Received) {
        let request = FakeAgentSettings.fixtures.appending(path: "permission-request.json").path
        let requirement = isApplication ? ["--answerer-requirement", "cdhash H\"\(try codeHashOfThisProcess())\""] : []
        let process = try FakeAgentSettings.sessionProcess(
            turns: ["command-turn"], mode: "askPermission", environment: ["FAKE_AGENT_PERMISSION_REQUEST": request], arguments: requirement)
        let location = try SocketLocation(path: process.socketPath)
        let thread = try SessionClient(location: location).createThread(agent: "claude-code", folder: process.directory.path)
        let attachment = try SessionClient(location: location).attachThread(thread.identifier)
        let received = Received()
        received.follow(attachment)
        try attachment.send(message: "Create the file.")
        return (process, attachment, received)
    }

    @Test func theAnswerOfTheAppAllowsTheCallOfTheAgent() async throws {
        let (process, attachment, received) = try start(isApplication: true)
        defer { process.stop() }
        #expect(await eventually { received.request != nil })
        let request = try #require(received.request)
        #expect(request.toolName == "Bash")
        #expect(try SessionClient(location: SocketLocation(path: process.socketPath)).threads().first?.state == "needsUser")
        try attachment.answer(permission: request.identifier, allows: true)
        #expect(await eventually { received.decision != nil })
        #expect(received.decision == #"{"type":"fake_hook","decision":"allow"}"#)
        #expect(received.end == PermissionEnd(identifier: request.identifier, outcome: .allowed))
    }

    @Test func aDenialOfTheAppReachesTheAgentWithItsMessage() async throws {
        let (process, attachment, received) = try start(isApplication: true)
        defer { process.stop() }
        #expect(await eventually { received.request != nil })
        try attachment.answer(permission: try #require(received.request).identifier, allows: false, message: "Use another file.")
        #expect(await eventually { received.decision != nil })
        #expect(received.decision == #"{"type":"fake_hook","decision":"deny: Use another file."}"#)
    }

    @Test func aProgramThatIsNotTheAppCannotAnswerAndAStopRefusesTheRequest() async throws {
        let (process, attachment, received) = try start(isApplication: false)
        defer { process.stop() }
        #expect(await eventually { received.request != nil })
        let request = try #require(received.request)
        try attachment.answer(permission: request.identifier, allows: true)
        #expect(await eventually { !received.failures.isEmpty })
        #expect(received.failures == ["Only OpenRun.app answers a permission request."] && received.decision == nil)
        // A stop ends the request and then the agent with its hook, so no call runs.
        try attachment.stop()
        #expect(await eventually { received.conversation.contains { if case .processEnded = $0.kind { true } else { false } } })
        #expect(received.end == PermissionEnd(identifier: request.identifier, outcome: .cancelled) && received.decision == nil)
    }

    @Test func aProgramOutsideEveryThreadCannotAskForAPermission() async throws {
        let process = try FakeAgentSettings.sessionProcess()
        defer { process.stop() }
        let client = try SessionClient(location: SocketLocation(path: process.socketPath))
        #expect(throws: SessionConnectionError.self) { _ = try client.requestToolPermission(Data("{}".utf8)) }
    }
}
