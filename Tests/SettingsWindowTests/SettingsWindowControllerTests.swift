import AppKit
import Settings
import Testing
@testable import SettingsWindow

@MainActor @Suite struct SettingsWindowControllerTests {
    private let controller = SettingsWindowController { "mode " + $0 }

    /// The default text of each setting, as the session process gives them.
    private var defaults: [String: String] {
        let values = SettingValues()
        return Dictionary(uniqueKeysWithValues: SettingName.allCases.map { ($0.rawValue, values.text(of: $0)) })
    }

    @Test func eachSettingHasOneControlInOnePane() {
        #expect(controller.panes.map(\.pane.title) == ["General", "Appearance", "Terminal", "Agents"])
        controller.show(defaults)
        let names = controller.panes.flatMap { $0.controls.keys }
        #expect(Set(names) == Set(SettingName.allCases.map(\.rawValue)) && names.count == SettingName.allCases.count)
        #expect(controller.window?.contentViewController is NSTabViewController)
        let links = controller.panes[0].controls["open-links-in"] as? ChoiceSettingControl
        #expect(links?.popup.itemTitles == ["In the Default Browser", "In a Web Page Beside the Work"])
        // Each pane groups its settings in sections with a heading, so a user sees what each one does.
        #expect(controller.panes[0].pane.sections.map(\.title) == ["Notifications", "Links", "Limits"])
        #expect(controller.panes[2].pane.sections.map(\.title) == ["Keyboard", "Scrollback", "Paste", "New Terminals"])
    }

    @Test func aPaneShowsTheHeadingOfEachSectionOverItsSettings() throws {
        let pane = SettingsPane(title: "Test", symbolName: "gearshape", sections: [
            SettingsSection(title: "Notifications", rows: [SettingRow(name: "notifications", label: "") { FlagSettingControl(title: "Notify me") }]),
            SettingsSection(title: "Links", note: "Where a link opens.", rows: [
                SettingRow(name: "open-links-in", label: "Open links") { ChoiceSettingControl([("a", "A")]) },
            ]),
        ])
        let controller = SettingsPaneController(pane)
        controller.loadViewIfNeeded()
        let grid = try #require(controller.view.subviews.first as? NSGridView)
        let texts = grid.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(texts == ["Notifications", "", "Links", "Where a link opens.", "Open links:"])
        #expect(pane.rows.map(\.name) == ["notifications", "open-links-in"] && controller.controls.count == 2)
        // The second heading stands apart from the section over it, and each heading goes over both columns.
        #expect(grid.row(at: 2).topPadding > grid.row(at: 0).topPadding && grid.cell(atColumnIndex: 1, rowIndex: 2).contentView === grid.cell(atColumnIndex: 0, rowIndex: 2).contentView)
    }

    @Test func theControlsShowTheTextsAndTellAChangeWithTheNameOfTheSetting() throws {
        var changes: [String] = []
        controller.change = { changes.append("\($0)=\($1)") }
        controller.show(defaults)
        let agents = try #require(controller.panes.last)
        let mode = try #require(agents.controls["claude-code-permission-mode"] as? ChoiceSettingControl)
        // The words of the modes are the ones of the host.
        #expect(mode.popup.itemTitles == ["mode plan", "mode dontAsk", "mode default", "mode acceptEdits", "mode auto"])
        #expect(mode.popup.titleOfSelectedItem == "mode default")
        mode.popup.selectItem(at: 3)
        mode.choose()
        let size = try #require(controller.panes[1].controls["font-size"] as? NumberSettingControl)
        #expect(size.field.stringValue == "13")
        size.field.stringValue = "15"
        size.typed()
        #expect(changes == ["claude-code-permission-mode=acceptEdits", "font-size=15"])
        // The texts of the session process show again, as after a refused change.
        controller.show(defaults)
        #expect(size.field.stringValue == "13" && mode.popup.titleOfSelectedItem == "mode default")
    }

    @Test func theFontOfTheSystemComesFirstAndEachFontHasOneWidth() {
        let fonts = SettingsPane.fixedPitchFonts
        #expect(fonts.first == "SF Mono" && fonts.contains("Menlo") && !fonts.contains("Helvetica") && Set(fonts).count == fonts.count)
    }
}
