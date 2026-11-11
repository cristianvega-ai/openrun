import AppKit
import Testing

@testable import ChatView

@MainActor struct ChatFindTests {
    @Test func findShowsTheNewestMatchAndMovesThroughThem() {
        let controller = ChatViewController(facts: ChatPictureFacts.facts)
        controller.view.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        controller.show(SampleConversation.transcript)
        controller.view.layoutSubtreeIfNeeded()
        controller.showFind()
        controller.findBar.field.stringValue = "transcript"
        controller.find("transcript")
        let count = controller.findMatches.count
        #expect(count > 5)
        #expect(controller.findIndex == count - 1)
        controller.moveFind(by: 1)
        #expect(controller.findIndex == 0)
        #expect(controller.findBar.countLabel.stringValue == "1 of \(count)")
        #expect(controller.scrollView.transcriptView.rowViews.views["user:1"] != nil)
        controller.hideFind()
        #expect(controller.findBar.isHidden)
    }
}

/// Facts for a chat in a test.
enum ChatPictureFacts {
    static let facts = ChatThreadFacts(threadIdentifier: "thread", title: "A thread", agentName: "Claude Code")
}
