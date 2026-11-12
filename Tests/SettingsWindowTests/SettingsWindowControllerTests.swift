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
        // The window offers only what works: links open in the default browser until the browser split exists.
        let links = controller.panes[0].controls["open-links-in"] as? ChoiceSettingControl
        #expect(links?.popup.itemTitles == ["The Default Browser"])
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
