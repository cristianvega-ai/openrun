import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct HeldMessageViewTests {
    @Test func aLongMessageShowsAtMostThreeLinesAndTheControlsAnswer() {
        let view = HeldMessageView()
        let long = String(repeating: "Then run the tests and commit the change. ", count: 30)
        view.show(ChatOutgoingMessage(text: long), agentName: "Codex", palette: ChatPalette(appearance: .graphite))
        #expect(view.label.stringValue == "Sends when Codex finishes")
        let lineHeight = ceil(view.text.font!.ascender - view.text.font!.descender + view.text.font!.leading)
        #expect(view.height(forWidth: 400) <= 2 * HeldMessageView.padding.height + HeldMessageView.headerHeight + 2 + 3 * lineHeight + 3)
        var actions: [String] = []
        view.editAction = { actions.append("edit") }
        view.deleteAction = { actions.append("delete") }
        view.editButton.performClick(nil)
        view.deleteButton.performClick(nil)
        #expect(actions == ["edit", "delete"])
    }
}
