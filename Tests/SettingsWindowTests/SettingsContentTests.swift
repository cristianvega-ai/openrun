import AppKit
import Testing
@testable import SettingsWindow

/// The right part of the settings window.
@MainActor @Suite struct SettingsContentTests {
    @Test func oneOfThePanesShowsUnderItsTitle() {
        let panes = ["General", "Accounts"].map { SettingsPaneController(SettingsPane(title: $0, symbolName: "gearshape", rows: [])) }
        let content = SettingsContentController(panes: panes)
        #expect(content.view.subviews.count == 2 && content.titleLabel.stringValue == "General" && panes.map(\.view.isHidden) == [false, true])
        content.show(pane: 1)
        #expect(content.titleLabel.stringValue == "Accounts" && content.shownPane == 1 && panes.map(\.view.isHidden) == [true, false])
    }
}
