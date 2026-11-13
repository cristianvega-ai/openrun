import AppKit
import Testing
@testable import SettingsWindow

/// The list of the panes at the left of the settings window.
@MainActor @Suite struct SettingsSidebarTests {
    @Test func aRowOfTheListHasTheIconAndTheTitleOfItsPane() {
        let cell = SettingsSidebarCellView(title: "Accounts", symbolName: "person.crop.circle")
        #expect(cell.textField?.stringValue == "Accounts" && cell.imageView?.image != nil && cell.accessibilityLabel() == "Accounts")
        #expect(cell.frame.height == SettingsSidebarCellView.height)
    }

    @Test func theListHasALineBetweenTwoGroupsOfPanes() {
        let panes = ["General", "Terminal", "Accounts"].map { SettingsPane(title: $0, symbolName: "gearshape", rows: []) }
        let sidebar = SettingsSidebarController(groups: [[panes[0], panes[1]], [panes[2]]])
        var chosen: [Int] = []
        sidebar.chose = { chosen.append($0) }
        sidebar.select(pane: 2)
        sidebar.table.selectRowIndexes([1], byExtendingSelection: false)
        #expect(sidebar.items == [0, 1, nil, 2] && sidebar.table.numberOfRows == 4 && chosen == [2, 1])
        // A line is lower than a pane and takes no selection. Each other row shows the title of its pane.
        #expect(sidebar.tableView(sidebar.table, heightOfRow: 2) < SettingsSidebarCellView.height && sidebar.tableView(sidebar.table, selectionIndexesForProposedSelection: [2]) == [1])
        let cell = sidebar.tableView(sidebar.table, viewFor: nil, row: 3) as? SettingsSidebarCellView
        #expect(cell?.textField?.stringValue == "Accounts" && !(sidebar.tableView(sidebar.table, viewFor: nil, row: 2) is SettingsSidebarCellView))
        #expect(sidebar.view.fittingSize.width == SettingsSidebarController.width && sidebar.searchField.placeholderString == "Search")
    }
}
