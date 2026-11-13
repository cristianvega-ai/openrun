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
        #expect(controller.panes.map(\.pane.title) == ["General", "Appearance", "Terminal", "Accounts", "Claude Code", "Limits"])
        controller.show(defaults)
        let names = controller.panes.flatMap { $0.controls.keys }
        #expect(Set(names) == Set(SettingName.allCases.map(\.rawValue)) && names.count == SettingName.allCases.count)
        let links = controller.panes[0].controls["open-links-in"] as? ChoiceSettingControl
        #expect(links?.popup.itemTitles == ["In the Default Browser", "In a Web Page Beside the Work"])
        // The accounts of both agents have a pane of their own, apart from the values of a new thread.
        #expect(controller.panes[3].pane.sections.map(\.title) == ["Claude Code", "Codex"] && controller.panes[3].pane.rows.map(\.name) == ["claude-code-accounts", "codex-accounts"])
        #expect(controller.panes[4].pane.rows.map(\.name) == ["claude-code-model", "claude-code-permission-mode", "claude-code-program"])
        #expect(controller.panes[5].pane.rows.map(\.name) == ["session-limit", "agent-process-limit"])
        #expect(controller.panes[0].pane.sections.map(\.title) == ["Notifications", "Links"])
        #expect(controller.panes[2].pane.sections.map(\.title) == ["Keyboard", "Scrollback", "Paste", "New Terminals"])
    }

    @Test func theListAtTheLeftChoosesThePaneThatShows() {
        let sidebar = controller.sidebar, content = controller.content
        #expect(sidebar.items == [0, 1, 2, nil, 3, 4, nil, 5] && sidebar.table.selectedRow == 0 && content.titleLabel.stringValue == "General")
        #expect(controller.panes.map(\.view.isHidden) == [false, true, true, true, true, true])
        sidebar.table.selectRowIndexes([4], byExtendingSelection: false)
        #expect(content.titleLabel.stringValue == "Accounts" && content.shownPane == 3 && controller.panes.map(\.view.isHidden) == [true, true, true, false, true, true])
        // The window has the colors and the top rows of the main window, and one width.
        let window = controller.window
        #expect(window?.styleMask.contains(.fullSizeContentView) == true && window?.contentMinSize.width == window?.contentMaxSize.width && window?.title == "Settings")
    }

    @Test func aPaneShowsEachSectionAsACardUnderItsHeading() throws {
        let pane = SettingsPane(title: "Test", symbolName: "gearshape", sections: [
            SettingsSection(rows: [SettingRow(name: "notifications", label: "Notifications", note: "macOS tells you.") { FlagSettingControl() }]),
            SettingsSection(title: "Links", note: "Where a link opens.", rows: [
                SettingRow(name: "open-links-in", label: "Open links") { ChoiceSettingControl([("a", "A")]) },
                SettingRow(name: "commands", label: "Commands") { EntryListSettingControl() },
            ]),
        ])
        let controller = SettingsPaneController(pane)
        controller.loadViewIfNeeded()
        let stack = try #require(controller.view as? NSStackView)
        let texts = stack.arrangedSubviews.map { ($0 as? NSTextField)?.stringValue ?? "card" }
        #expect(texts == ["card", "Links", "Where a link opens.", "card"])
        #expect(pane.rows.map(\.name) == ["notifications", "open-links-in", "commands"] && controller.controls.count == 3)
        // A row has the name and the note of its setting at the left of its control. A list fills its card.
        let cards = stack.arrangedSubviews.compactMap { $0 as? SettingsCardView }
        let first = try #require(cards[0].rows.rows.first as? SettingRowView)
        #expect(first.label?.stringValue == "Notifications" && first.note?.stringValue == "macOS tells you." && first.arrangedSubviews.last is NSSwitch)
        #expect(cards[1].rows.rows.count == 2 && cards[1].rows.rows[1] is SettingRowsView && cards[1].rows.arrangedSubviews.count == 3)
    }

    @Test func theControlsShowTheTextsAndTellAChangeWithTheNameOfTheSetting() throws {
        var changes: [String] = []
        controller.change = { changes.append("\($0)=\($1)") }
        controller.show(defaults)
        let agents = controller.panes[4]
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
