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
        #expect(!list.emptyView.isHidden && list.emptyView.message.stringValue == "No Sessions in Progress")
        list.show(SessionsListContent(title: "openrun", rows: [], agents: []))
        list.arrange(filter: .all, order: .manual)
        #expect(!list.emptyView.isHidden && list.emptyView.message.stringValue == "No Sessions")
        #expect(list.emptyView.startButton.action == #selector(SessionsListController.showNewSessionMenu))
    }
}
