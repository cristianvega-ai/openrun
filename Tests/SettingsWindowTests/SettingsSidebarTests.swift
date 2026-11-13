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
}
