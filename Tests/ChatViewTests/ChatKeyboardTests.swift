import AgentConversation
import AppKit
import Testing

@testable import ChatView

/// Tab goes from the composer to the newest request that waits, and then
/// through the lines that open.
@MainActor struct ChatKeyboardTests {
    @Test func tabGoesFromTheComposerToTheRequestAndThenToTheLines() throws {
        let controller = ChatViewController(facts: ChatPictureTests.facts)
        let window = PictureWindow(controller: controller, size: NSSize(width: 800, height: 900), appearance: .aqua)
        defer { window.close() }
        controller.show(Transcript(events: SampleConversation.firstTurn + SampleConversation.failedTurn + SampleConversation.waitingTurn))
        controller.view.layoutSubtreeIfNeeded()
        let rows = controller.transcriptView.rowViews.views.values
        let box = try #require(rows.compactMap { ($0 as? PermissionRequestRowView)?.box }.first { $0.superview != nil })
        let field = controller.composer.textView
        #expect(field.nextKeyView === box.messageField)
        #expect(box.messageField.nextKeyView === box.denyButton)
        #expect(box.denyButton.nextKeyView === box.allowButton)
        let line = try #require(box.allowButton.nextKeyView as? DisclosureLineView)
        #expect(line.action != nil)
        window.window.makeFirstResponder(field)
        field.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect((window.window.firstResponder as? NSTextView)?.delegate === box.messageField)
        #expect(field.string.isEmpty)
    }
}
