import AppKit
import SessionProtocol
import Settings
import TerminalView
import Testing
@testable import OpenRunApplication

@MainActor @Suite struct LiveSettingsTests {
    private func setting(_ name: String, _ text: String) -> SettingSummary {
        SettingSummary(name: name, text: text, isProtected: false)
    }

    @Test func theValuesComeFromTheTextsOfTheSessionProcess() {
        let values = LiveSettings.values(from: [
            setting("font-size", "17"), setting("option-as-alt", "both"), setting("session-limit", "7"),
            setting("ask-before-unsafe-paste", "off"), setting("setting-of-a-later-build", "x"), setting("scrollback-limit", "many"),
        ])
        #expect(values.fontSize == 17 && values.optionAsAlt == .both && values.sessionLimit == 7 && !values.asksBeforeUnsafePaste)
        #expect(values.scrollbackLimit == 10_000 && values.fontName == "SF Mono")
    }

    @Test func aTerminalViewTakesTheFontTheOptionKeysAndTheScrollbackLimit() throws {
        let view = try TerminalView()
        let values = LiveSettings.values(from: [
            setting("font-name", "Menlo"), setting("font-size", "18"), setting("option-as-alt", "neither"), setting("scrollback-limit", "500"),
        ])
        LiveSettings.apply(values, to: view)
        #expect(view.fontName == "Menlo" && view.standardFontSize == 18 && view.optionKeyRule == .neither && view.scrollbackLimit == 500)
        LiveSettings.apply(SettingValues(), to: view)
        #expect(view.fontName == nil && view.standardFontSize == 13 && view.optionKeyRule == .left && view.scrollbackLimit == 10_000)
    }
}
