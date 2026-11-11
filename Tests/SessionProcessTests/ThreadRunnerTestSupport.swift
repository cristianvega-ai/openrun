import AgentConversation
import AgentThreads
import Foundation
import SessionProcessHarness
import Synchronization
@testable import SessionProcess

/// The fake agent in place of Claude Code, so that no test runs the real
/// agent and spends the subscription of the owner.
enum FakeAgentSettings {
    static let fixtures = URL(fileURLWithPath: "../ClaudeCodeAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
    static let executable = RunningSessionProcess.productsDirectory.appendingPathComponent("fake-agent").path

    /// - Parameter turns: The names of the recorded turns that the agent plays, in order.
    static func make(turns: [String] = ["plain-turn"], mode: String = "replay", environment: [String: String] = [:]) -> AgentLaunchSettings {
        let paths = turns.map { fixtures.appending(path: $0 + ".jsonl").path }
        let base = ["PATH": "/usr/bin:/bin", "FAKE_AGENT_TURNS": paths.joined(separator: ":"), "FAKE_AGENT_MODE": mode]
        return AgentLaunchSettings(program: executable, environment: base.merging(environment) { $1 }, hookCommand: "/usr/bin/false", hookArguments: [])
    }

    /// A real session process whose threads run the fake agent with the
    /// environment of the test, and never the login shell of the user.
    static func sessionProcess(
        turns: [String] = ["plain-turn"], mode: String = "replay", environment: [String: String] = [:], arguments: [String] = []
    ) throws -> RunningSessionProcess {
        let settings = make(turns: turns, mode: mode, environment: environment)
        return try RunningSessionProcess(arguments: ["--agent-program", executable, "--own-environment-for-agents"] + arguments, environment: settings.environment)
    }

    static func record(folder: String = NSTemporaryDirectory()) -> ThreadRecord {
        ThreadRecord(agent: .claudeCode, folder: folder, model: "claude-haiku-5-5", permissionMode: "default")
    }
}

/// What a runner gave to one attached client, in order.
final class ThreadDeliveries: Sendable {
    private let deliveries = Mutex<[ThreadDelivery]>([])

    var listener: ThreadRunner.Listener {
        { [self] delivery in deliveries.withLock { $0.append(delivery) } }
    }

    /// The events, decoded, without the marks.
    var events: [ConversationEvent] {
        deliveries.withLock { $0 }.compactMap { delivery in
            guard case .event(let data) = delivery else { return nil }
            return try? JSONDecoder().decode(ConversationEvent.self, from: data)
        }
    }

    /// The number of events before the mark that the replay is complete, or nil before the mark.
    var replayCount: Int? {
        deliveries.withLock { $0 }.firstIndex { if case .replayComplete = $0 { true } else { false } }
    }

    /// What the mark of the complete replay says about earlier events, or nil before the mark.
    var hasEarlierEvents: Bool? {
        deliveries.withLock { $0 }.lazy.compactMap { if case .replayComplete(let hasEarlier) = $0 { hasEarlier } else { nil } }.first
    }

    var isClosed: Bool {
        deliveries.withLock { $0 }.contains { if case .closed = $0 { true } else { false } }
    }
}

extension ThreadRunner {
    /// The events that the runner keeps, decoded.
    var keptEvents: [ConversationEvent] {
        buffer.entries.compactMap { try? JSONDecoder().decode(ConversationEvent.self, from: $0.data) }
    }

    /// The text of each message of the agent in the transcript.
    var agentTexts: [String] {
        transcript.items.compactMap { if case .agentMessage(let message) = $0.content { message.text } else { nil } }
    }
}
