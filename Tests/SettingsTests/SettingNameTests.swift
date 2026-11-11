@testable import Settings
import Testing

@Suite struct SettingNameTests {
    /// The names are the keys of `settings.json` and the words of the tool,
    /// so a change must not pass unseen.
    @Test func theNamesAreFixed() {
        #expect(SettingName.allCases.map(\.rawValue) == [
            "theme", "font-name", "font-size", "option-as-alt", "scrollback-limit", "new-session-commands",
            "open-links-in", "notifications", "session-limit", "ask-before-unsafe-paste",
        ])
        #expect(SettingName.allCases.filter { $0.isProtected } == [.sessionLimit, .asksBeforeUnsafePaste])
    }

    @Test(arguments: SettingName.allCases)
    func eachDefaultIsAValueOfItsKind(name: SettingName) {
        #expect(name.kind.accepts(name.defaultValue))
    }

    @Test func anUnknownNameIsRefusedWithAnEscapedMessage() throws {
        #expect(try SettingName.named("font-size") == .fontSize)
        #expect(throws: SettingError.unknownName("Font-Size")) { try SettingName.named("Font-Size") }
        let error = SettingError.unknownName("x\u{1B}]0;title\u{7}")
        #expect(error.description == #"OpenRun has no setting "x\u{1B}]0;title\u{7}". Run `openrun settings list` to see the settings."#)
    }

    @Test func theMessagesTellTheRule() {
        #expect(SettingError.invalidValue(.fontSize).description == "The setting font-size takes a whole number from 6 to 72.")
        #expect(SettingError.invalidValue(.optionAsAlt).description == "The setting option-as-alt takes one of left, both, neither.")
        #expect(SettingError.protectedSetting(.sessionLimit).description
            == "The setting session-limit is protected. Change it in the settings window of OpenRun.")
    }
}
