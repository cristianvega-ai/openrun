import AgentConversation
import AppKit
import ClaudeCodeAgent
import Testing

@testable import ChatView

/// Plays recorded turns of Claude Code into the chat, one event at a time,
/// as a host does while the agent writes.
@MainActor struct ChatReplayTests {
    nonisolated static let fixtures = URL(fileURLWithPath: "../ClaudeCodeAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath))
        .standardizedFileURL

    /// The kinds of rows at the end of the turn, by name.
    nonisolated static let expectedKinds: [String: Set<String>] = [
        "plain-turn": ["userMessage", "agentText"],
        "command-turn": ["userMessage", "toolCalls", "agentText"],
        "denied-turn": ["userMessage", "toolCalls", "agentText"],
        "edit-turn": ["userMessage", "toolCalls", "fileChange", "agentText"],
        "sub-agent-turn": ["userMessage", "task", "agentText"],
        "stopped-turn": ["notice", "toolCalls", "turnEnd"],
        "authentication-failure": ["notice"],
    ]

    @Test(arguments: expectedKinds.keys.sorted())
    func eachEventUpdatesTheRowsAsAFullBuildDoes(_ name: String) throws {
        var decoder = ClaudeCodeOutputDecoder()
        let bytes = Array(try Data(contentsOf: Self.fixtures.appending(path: name + ".jsonl")))
        let events = decoder.decode(bytes) + decoder.finish()
        let controller = ChatViewController(facts: ChatThreadFacts(threadIdentifier: "replay", title: "Replay", agentName: "Claude Code"))
        controller.view.frame.size = NSSize(width: 700, height: 500)
        var transcript = Transcript()
        controller.show(transcript)
        for event in events {
            let change = transcript.apply(event)
            controller.update(transcript, change: change)
            controller.view.layoutSubtreeIfNeeded()
            var builder = TranscriptRowBuilder()
            let full = builder.rows(for: transcript, changedItems: nil, showsEarlierItems: transcript.removedItemCount > 0)
            #expect(controller.transcriptView.rows == full, "after \(event)")
            #expect(controller.scrollView.distanceFromBottom == 0)
        }
        let kinds = Set(controller.transcriptView.rows.map { "\($0.kind)".prefix { $0 != "(" } }.map(String.init))
        #expect(kinds.isSuperset(of: try #require(Self.expectedKinds[name])), "\(kinds)")
    }
}
