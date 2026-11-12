import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionsEmptyViewTests {
    @Test func anEmptyListSaysWhyAndOffersANewSession() {
        let (list, _, window, _) = makeSessionsList()
        defer { window.close() }
        #expect(list.emptyView.isHidden)
        list.arrange(filter: .inProgress, order: .manual)
        var content = list.content
        content.rows[0].isInProgress = false
        list.show(content)
        #expect(!list.emptyView.isHidden && list.emptyView.message.stringValue == "Nothing in Progress")
        list.show(SessionsListContent(title: "openrun", rows: [], agents: []))
        list.arrange(filter: .all, order: .manual)
        #expect(!list.emptyView.isHidden && list.emptyView.message.stringValue == "No Threads or Terminals")
        #expect(list.emptyView.startButton.action == #selector(SessionsListController.showNewSessionMenu))
        // The host names an empty list, and the button offers a thread or a terminal.
        list.show(SessionsListContent(title: "openrun", emptyMessage: "Nothing in openrun Yet"))
        #expect(list.emptyView.message.stringValue == "Nothing in openrun Yet" && list.emptyView.startButton.title == "New Thread or Terminal")
    }
}
