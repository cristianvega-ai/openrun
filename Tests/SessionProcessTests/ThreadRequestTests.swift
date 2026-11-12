import AgentConversation
import AgentThreads
import ClaudeCodeAgent
import DataStorage
import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing

/// The agent threads through the socket of a real session process, with
/// the fake agent in place of Claude Code.
@Suite struct ThreadRequestTests {
    /// The events that an attachment received, in order.
    private final class Received: Sendable {
        let events = Mutex<[ThreadAttachment.Event]>([])

        func follow(_ attachment: ThreadAttachment) {
            attachment.startReceiving { [self] event in events.withLock { $0.append(event) } }
        }

        var all: [ThreadAttachment.Event] { events.withLock { $0 } }
        var conversation: [ConversationEvent] { all.compactMap { if case .event(let event) = $0 { event } else { nil } } }
        var hasTurnEnd: Bool { conversation.contains { if case .turnEnded = $0.kind { true } else { false } } }
    }

    @Test func aNewThreadTakesTheModelOfTheSettings() throws {
        let process = try FakeAgentSettings.sessionProcess()
        defer { process.stop() }
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        try client.changeSetting(named: "claude-code-model", to: "sonnet")
        let thread = try client.createThread(agent: "claude-code", folder: process.directory.path)
        #expect(thread.model == "sonnet" && thread.permissionMode == "default")
        // A thread that names its model keeps it.
        #expect(try client.createThread(agent: "claude-code", folder: process.directory.path, model: "haiku").model == "haiku")
    }

    @Test func aClientReadsTheEarlierTurnsFromTheHistoryOfTheAgent() async throws {
        let settings = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: settings) }
        let process = try FakeAgentSettings.sessionProcess(environment: ["CLAUDE_CONFIG_DIR": settings.path])
        defer { process.stop() }
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        let thread = try client.createThread(agent: "claude-code", folder: process.directory.path)
        // No turn ran, so the agent has no history of the thread.
        #expect(try client.threadHistory(thread.identifier).events.isEmpty)
        _ = try client.sendThreadMessage(thread.identifier, text: "One.")
        #expect(await eventually { (try? client.threads().first?.state) == "finishedTurn" })

        // The file is where Claude Code keeps the history of the conversation.
        let record = try #require(try ThreadStore(dataFolder: DataFolder(path: process.directory.path)).load().list.thread(thread.identifier))
        let conversation = try #require(UUID(uuidString: record.conversationIdentifier))
        let file = ClaudeCodeHistoryLocation.fileURL(configurationFolder: settings, workingFolder: thread.folder, conversationIdentifier: conversation)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: FakeAgentSettings.fixtures.appending(path: "history.jsonl"), to: file)
        let page = try client.threadHistory(thread.identifier)
        #expect(page.before == nil && page.events.count == 5)
        #expect(page.events.first?.kind == .userMessage(UserMessage(
            identifier: "00000000-0000-4000-8000-000000000195",
            text: "Run the command `touch held.txt` with your Bash tool. Then reply with the single word ok.", isAccepted: true)))
        // The start of the history has no page before it, and an unknown thread has no history.
        #expect(try client.threadHistory(thread.identifier, before: 0).events.isEmpty)
        #expect(throws: SessionConnectionError.self) { try client.threadHistory(UUID()) }
    }

    @Test func aClientMakesAThreadSendsAMessageAndFollowsTheTurn() async throws {
        let process = try FakeAgentSettings.sessionProcess()
        defer { process.stop() }
        let location = try SocketLocation(path: process.socketPath)
        let client = try SessionClient(location: location)
        #expect(client.capabilities.threads)
        let thread = try client.createThread(agent: "claude-code", folder: process.directory.path, name: "Notes")
        #expect(thread.name == "Notes" && thread.state == "idle" && thread.model == "opus")
        #expect(try client.threads() == [thread])

        let attachment = try SessionClient(location: location).attachThread(thread.identifier)
        #expect(attachment.summary == thread)
        let received = Received()
        received.follow(attachment)
        try attachment.send(message: "Reply with the single word ok.")
        #expect(await eventually { received.hasTurnEnd })
        #expect(received.all.first == .replayComplete(hasEarlierEvents: false))
        #expect(received.all.contains { if case .messageSent = $0 { true } else { false } })
        #expect(Transcript(events: received.conversation).state == .finishedTurn)

        // A client that attaches later gets the same events, before its mark.
        let later = try SessionClient(location: location).attachThread(thread.identifier)
        let replay = Received()
        replay.follow(later)
        #expect(await eventually { replay.all.contains(.replayComplete(hasEarlierEvents: false)) })
        #expect(replay.conversation == received.conversation && replay.all.last == .replayComplete(hasEarlierEvents: false))
        let listed = try #require(try client.threads().first)
        #expect(listed.state == "finishedTurn" && listed.title == "Reply with the single word ok." && listed.isProcessRunning)

        try client.renameThread(thread.identifier, to: "Release")
        #expect(try client.threads().first?.name == "Release")
        try client.closeThread(thread.identifier)
        #expect(await eventually { received.all.last == .threadEnded && replay.all.last == .threadEnded })
        #expect(try client.threads().isEmpty)
        attachment.shutdown()
        later.shutdown()
    }

    @Test func aRequestThatCannotWorkGetsAFailureWithTheReason() async throws {
        let process = try FakeAgentSettings.sessionProcess()
        defer { process.stop() }
        let client = try SessionClient(location: SocketLocation(path: process.socketPath))
        func message(_ request: () throws -> Void) -> String {
            do { try request() } catch SessionConnectionError.requestFailed(let failure) { return failure.message } catch { return "\(error)" }
            return "no failure"
        }
        let unknown = UUID()
        #expect(message { _ = try client.createThread(agent: "gemini", folder: "/") } == "OpenRun runs threads with Claude Code and with Codex. Give claude-code or codex as the agent.")
        #expect(message { _ = try client.createThread(agent: "claude-code", folder: "/no/such/folder") }.hasPrefix("The folder of a thread must be"))
        #expect(message { _ = try client.sendThreadMessage(unknown, text: "Hello") } == "No thread has the identifier \(unknown.uuidString.lowercased()).")
        #expect(message { try client.stopThread(unknown) }.hasPrefix("No thread has the identifier"))
        #expect(message { _ = try client.attachThread(unknown) }.hasPrefix("No thread has the identifier"))
        // The connection goes on after each failure.
        #expect(try client.threads().isEmpty)
    }
}
