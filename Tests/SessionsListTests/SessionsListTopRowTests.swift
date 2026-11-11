import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct SessionsListTopRowTests {
    private func choose(_ title: String, in menu: NSMenu) throws {
        let item = try #require(menu.items.first { $0.title == title })
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    @Test func theMenuSetsTheFilterAndTheOrderAndTheHostKeepsThem() throws {
        let (list, host, window, _) = makeSessionsList()
        defer { window.close() }
        #expect(list.titleLabel.stringValue == "openrun" && list.filterLabel.isHidden)
        let menu = list.arrangementMenu()
        #expect(menu.items.filter { $0.state == .on }.map(\.title) == ["All", "Manual"])
        try choose("In Progress", in: menu)
        #expect(list.shownTitles == ["Repair the resize"] && list.filterLabel.stringValue == "In Progress" && !list.filterLabel.isHidden)
        try choose("Name", in: list.arrangementMenu())
        #expect(host.arrangements.map(\.0) == [.inProgress, .inProgress] && host.arrangements.map(\.1) == [.manual, .name])
        #expect(list.arrangementMenu().items.filter { $0.state == .on }.map(\.title) == ["In Progress", "Name"])
    }
}
