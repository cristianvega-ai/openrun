import AgentConversation
import AppKit
import Testing
@testable import ChatView

/// Opt in with OPENRUN_RENDER_OUTPUT to save pictures of the chat.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] != nil))
struct ChatPictureTests {
    static let facts = ChatThreadFacts(
        threadIdentifier: "thread-1", title: "Show earlier items", agentName: "Claude Code", accountName: "Work",
        model: ChatChoice(identifier: "claude-opus-5-5", title: "Opus 5.5"),
        models: [ChatChoice(identifier: "claude-opus-5-5", title: "Opus 5.5"), ChatChoice(identifier: "claude-sonnet-5-5", title: "Sonnet 5.5")],
        permissionMode: ChatChoice(identifier: "default", title: "Ask"),
        permissionModes: [ChatChoice(identifier: "default", title: "Ask"), ChatChoice(identifier: "plan", title: "Plan")],
        folder: "~/Projects/openrun", branch: "main")

    private func output() throws -> URL {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func picture(_ name: String, _ transcript: Transcript, size: NSSize = NSSize(width: 820, height: 900),
                         facts: ChatThreadFacts = Self.facts, prepare: (ChatViewController) -> Void = { _ in }) throws {
        let output = try output()
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let controller = ChatViewController(facts: facts)
            let window = PictureWindow(controller: controller, size: size, appearance: appearance)
            defer { window.close() }
            controller.show(transcript)
            prepare(controller)
            try window.capture(to: output.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    @Test func aLongConversation() throws {
        try picture("conversation", SampleConversation.transcript)
    }

    @Test func theStartWithOpenToolCalls() throws {
        try picture("start", SampleConversation.transcript, size: NSSize(width: 820, height: 1500)) { controller in
            controller.context.openedParts = ["group:tool:t1", "tool:t3", "file:e1"]
            controller.show(SampleConversation.transcript)
            controller.view.layoutSubtreeIfNeeded()
            controller.scrollView.contentView.scroll(to: .zero)
        }
    }

    @Test func streamingInTheMiddleOfACodeBlock() throws {
        try picture("streaming", Transcript(events: SampleConversation.firstTurn + SampleConversation.streamingTurn),
                    size: NSSize(width: 820, height: 700))
    }

    @Test func anEmptyThread() throws {
        try picture("empty", Transcript(), size: NSSize(width: 820, height: 600))
    }

    @Test func anAccountAtItsLimit() throws {
        var facts = Self.facts
        facts.condition = .atLimit(resetTime: Date().addingTimeInterval(5_400), otherAccounts: [ChatAccount(identifier: "p", name: "Personal")])
        try picture("limit", Transcript(events: SampleConversation.firstTurn), size: NSSize(width: 820, height: 700), facts: facts)
    }

    @Test func aNarrowAndAWidePane() throws {
        try picture("narrow", SampleConversation.transcript, size: NSSize(width: 360, height: 900))
        try picture("wide", SampleConversation.transcript, size: NSSize(width: 1400, height: 800))
    }
}
