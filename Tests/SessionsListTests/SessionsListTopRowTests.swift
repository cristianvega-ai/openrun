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

    @Test func theNewSessionMenuOffersEachAgentAndATerminal() throws {
        let (list, host, window, _) = makeSessionsList()
        defer { window.close() }
        let menu = list.newSessionMenu()
        #expect(menu.items.map(\.title) == ["New Claude Code Thread", "New Codex Thread", "", "New Terminal"])
        try choose("New Codex Thread", in: menu)
        try choose("New Terminal", in: menu)
        #expect(host.requests == [.thread(agent: "Codex"), .terminal(command: nil)])
        #expect(list.topRow.trailingItems.arrangedSubviews == [list.arrangementButton, list.newSessionButton])
        #expect(list.newSessionButton.accessibilityLabel() == "New Session")
    }

    @Test func theNewSessionMenuOffersAThreadUnderEachOtherAccountOfAnAgent() throws {
        let (list, host, window, _) = makeSessionsList()
        defer { window.close() }
        list.show(SessionsListContent(agents: ["Claude Code", "Codex"], accounts: ["Claude Code": ["Work", "Home"]]))
        let menu = list.newSessionMenu()
        #expect(menu.items.map(\.title) == [
            "New Claude Code Thread", "New Claude Code Thread on Work", "New Claude Code Thread on Home", "New Codex Thread", "", "New Terminal",
        ])
        try choose("New Claude Code Thread on Home", in: menu)
        try choose("New Claude Code Thread", in: menu)
        #expect(host.requests == [.thread(agent: "Claude Code", account: "Home"), .thread(agent: "Claude Code")])
    }

    @Test func theNewSessionMenuOffersATerminalWithEachCommandOfTheSettings() throws {
        let (list, host, window, _) = makeSessionsList()
        defer { window.close() }
        list.show(SessionsListContent(title: "openrun", terminalCommands: ["Claude Code", "Codex"]))
        let menu = list.newSessionMenu()
        #expect(menu.items.map(\.title) == ["New Terminal", "New Terminal with Claude Code", "New Terminal with Codex"])
        try choose("New Terminal with Codex", in: menu)
        #expect(host.requests == [.terminal(command: "Codex")])
    }
}
