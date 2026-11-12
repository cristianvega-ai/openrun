import Foundation
import Testing
import WindowLayout

@Suite struct LayoutPaneBrowsersTests {
    private let one = UUID(), two = UUID()
    private let page = LayoutBrowser(address: "http://localhost:3000/")

    @Test func aWebPageIsALeafOfARowAndStaysWhileASessionOfTheRowStays() throws {
        var layout = WindowLayout()
        layout.follow(sessions: [one, two])
        #expect(layout.addBrowser(page, beside: one, direction: .sideBySide) && !layout.addBrowser(page, beside: UUID(), direction: .stacked))
        let pane = try #require(layout.row(one)?.pane)
        #expect(pane.leaves == [one, page.identifier] && pane.sessions == [one] && pane.browsers == [page] && pane.threads.isEmpty)
        #expect(layout.browser(page.identifier) == page && layout.browser(one) == nil)
        // The file keeps the page with its address.
        #expect(try JSONDecoder().decode(LayoutPane.self, from: JSONEncoder().encode(pane)) == pane)
        layout.setAddress("https://example.com/docs", ofBrowser: page.identifier)
        #expect(layout.browser(page.identifier)?.address == "https://example.com/docs")
        // The page stays with its row, and a row with only a web page goes away.
        layout.follow(sessions: [one, two])
        #expect(layout.row(one)?.pane.leaves == [one, page.identifier])
        layout.follow(sessions: [two])
        #expect(layout.rows.map(\.identifier) == [two] && layout.browser(page.identifier) == nil)
    }

    @Test func aClosedWebPageGivesItsRoomToTheOtherHalf() {
        let other = LayoutBrowser(address: "about:blank")
        var layout = WindowLayout()
        layout.follow(sessions: [one])
        layout.addBrowser(page, beside: one, direction: .sideBySide)
        layout.addBrowser(other, beside: page.identifier, direction: .stacked)
        #expect(layout.row(one)?.pane.leaves == [one, page.identifier, other.identifier])
        layout.removeBrowser(page.identifier)
        #expect(layout.row(one)?.pane == .split(LayoutSplit(direction: .sideBySide, first: .session(one), second: .browser(other))))
        layout.removeBrowser(other.identifier)
        layout.removeBrowser(one)
        #expect(layout.row(one)?.pane == .session(one))
    }
}
