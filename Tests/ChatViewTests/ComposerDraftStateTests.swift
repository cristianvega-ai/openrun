import AgentConversation
import AppKit
import Testing
@testable import ChatView

/// A message that waits in the composer, and a draft, outlive the pane
/// of their chat (finding 10 of the state machine audit).
@MainActor @Suite struct ComposerDraftStateTests {
    @Test func heldMessageAndDraftSurviveComposerReplacement() {
        let first = ComposerView(palette: ChatPalette(appearance: .graphite))
        first.setBusy(true)
        first.textView.string = "submitted"
        first.submit()
        first.textView.string = "draft"
        let second = ComposerView(palette: first.palette)
        second.draft = first.draft
        #expect(second.logic.heldMessage?.text == "submitted")
        #expect(second.textView.string == "draft")
        var sent: [String] = []
        second.sendAction = { sent.append($0.text) }
        second.setBusy(false)
        #expect(sent == ["submitted"])
    }

    @Test func submittedMessagesDoNotEvictWithDrafts() {
        var drafts = ComposerDrafts()
        drafts.save(.init(heldMessage: ChatOutgoingMessage(text: "submitted")), for: "held")
        for index in 0...ComposerDrafts.countLimit {
            drafts.save(.init(text: "draft"), for: String(index))
        }
        #expect(drafts.draft(for: "held").heldMessage?.text == "submitted")
    }
}
