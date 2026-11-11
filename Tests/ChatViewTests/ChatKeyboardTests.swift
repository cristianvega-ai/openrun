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

/// At its minimum size, the pane shows a waiting request with its heading,
/// four lines of its text and its buttons, above a composer of one line.
@MainActor struct ChatMinimumSizeTests {
    @Test func aWaitingRequestFitsAtTheMinimumSize() throws {
        let controller = ChatViewController(facts: ChatPictureTests.facts)
        let window = PictureWindow(controller: controller, size: NSSize(width: 320, height: 1_000), appearance: .aqua)
        defer { window.close() }
        controller.view.frame.size = controller.minimumSize
        let command = (1...40).map { "echo \($0)" }.joined(separator: "\n")
        controller.show(Transcript(events: [TestEvents.user("1", "Go."), TestEvents.permission("p", "Bash", ["command": command])]))
        controller.composer.textView.string = "One\nTwo\nThree\nFour\nFive"
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        let oneLine = ComposerLayout(width: 320, textHeight: 0, lineHeight: 1, hasNote: false, hasImages: false, maximumFieldHeight: 0)
        let font = controller.context.palette.bodyFont
        #expect(controller.composer.frame.height <= oneLine.height + ceil(font.ascender - font.descender + font.leading))
        let row = try #require(controller.transcriptView.rowViews.views.values.compactMap { $0 as? PermissionRequestRowView }.first)
        row.layoutSubtreeIfNeeded()
        let visible = controller.scrollView.contentView.bounds
        let box = row.convert(row.box.frame, to: controller.transcriptView)
        #expect(visible.contains(box), "\(box)")
        let text = try #require(row.box.partViews.last as? DetailBoxView)
        #expect(text.frame.height >= 4 * (controller.context.palette.smallCodeFont.ascender - controller.context.palette.smallCodeFont.descender))
    }
}
