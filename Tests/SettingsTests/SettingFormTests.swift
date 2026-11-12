@testable import Settings
import Testing

@Suite struct SettingFormTests {
    @Test(arguments: SettingName.allCases)
    func eachDefaultRoundTripsThroughBothForms(name: SettingName) {
        let text = SettingTextForm.text(of: name.defaultValue)
        #expect(SettingTextForm.value(of: text, as: name.kind) == name.defaultValue)
        let stored = SettingStoredForm.stored(name.defaultValue)
        #expect(SettingStoredForm.value(from: stored, as: name.kind) == name.defaultValue)
    }

    @Test func theTextFormsAreTheOnesTheToolShows() {
        #expect(SettingTextForm.text(of: .wholeNumber(13)) == "13")
        #expect(SettingTextForm.text(of: .flag(true)) == "on")
        #expect(SettingTextForm.text(of: .flag(false)) == "off")
        #expect(SettingTextForm.text(of: .commands(NewSessionCommand.defaults))
            == #"[{"command":"","name":"Shell"},{"command":"claude","name":"Claude Code"},{"command":"codex","name":"Codex"}]"#)
    }

    @Test func aWholeNumberMustBeInItsRange() {
        let kind = SettingName.fontSize.kind
        #expect(SettingTextForm.value(of: " 6 ", as: kind) == .wholeNumber(6))
        #expect(SettingTextForm.value(of: "72", as: kind) == .wholeNumber(72))
        for bad in ["5", "73", "13.5", "", "thirteen", "1e1", "99999999999999999999"] {
            #expect(SettingTextForm.value(of: bad, as: kind) == nil)
        }
        #expect(SettingStoredForm.value(from: .number(13), as: kind) == .wholeNumber(13))
        #expect(SettingStoredForm.value(from: .number(13.5), as: kind) == nil)
        #expect(SettingStoredForm.value(from: .string("13"), as: kind) == nil)
    }

    @Test func aFlagAndAChoiceIgnoreCaseAndSpaces() {
        #expect(SettingTextForm.value(of: "Off", as: .flag) == .flag(false))
        #expect(SettingTextForm.value(of: " YES", as: .flag) == .flag(true))
        #expect(SettingTextForm.value(of: "1", as: .flag) == nil)
        #expect(SettingTextForm.value(of: "Both ", as: SettingName.optionAsAlt.kind) == .choice("both"))
        #expect(SettingTextForm.value(of: "right", as: SettingName.optionAsAlt.kind) == nil)
        #expect(SettingStoredForm.value(from: .integer(1), as: .flag) == nil)
    }

    @Test func textKeepsEveryCharacterAndRefusesControls() {
        let kind = SettingName.theme.kind
        #expect(SettingTextForm.value(of: " Solarized Light ", as: kind) == .text(" Solarized Light "))
        #expect(SettingTextForm.value(of: "", as: kind) == nil)
        #expect(SettingTextForm.value(of: "a\u{1B}b", as: kind) == nil)
        #expect(SettingTextForm.value(of: String(repeating: "x", count: 101), as: kind) == nil)
    }

    @Test func theCommandsNeedObjectsWithANameAndACommand() {
        let kind = SettingKind.commands
        #expect(SettingTextForm.value(of: "[]", as: kind) == .commands([]))
        #expect(SettingTextForm.value(of: #"[{"name":"Tests","command":"swift test"}]"#, as: kind)
            == .commands([NewSessionCommand(name: "Tests", commandLine: "swift test")]))
        #expect(SettingTextForm.value(of: #"[{"name":"a","command":"b","icon":"star"}]"#, as: kind)
            == .commands([NewSessionCommand(name: "a", commandLine: "b")]))
        let tooMany = "[" + Array(repeating: #"{"name":"a","command":"b"}"#, count: 21).joined(separator: ",") + "]"
        for bad in ["", "claude", #"{"name":"a","command":"b"}"#, #"[{"name":"a"}]"#,
                    #"[{"name":"a","command":1}]"#, #"[{"name":"a","command":"b\nc"}]"#, tooMany] {
            #expect(SettingTextForm.value(of: bad, as: kind) == nil)
        }
    }

    @Test func theAccountsNeedObjectsWithANameOfTheirOwnAndAFullPath() {
        let kind = SettingKind.accounts
        #expect(SettingTextForm.value(of: "[]", as: kind) == .accounts([]))
        let work = AgentAccount(name: "Work", settingsFolder: "/Users/me/.claude-work")
        #expect(SettingTextForm.value(of: #"[{"name":"Work","folder":"/Users/me/.claude-work"}]"#, as: kind) == .accounts([work]))
        #expect(SettingTextForm.text(of: .accounts([work])) == #"[{"folder":"/Users/me/.claude-work","name":"Work"}]"#)
        let tooMany = "[" + (0...10).map { #"{"name":"a\#($0)","folder":"/a"}"# }.joined(separator: ",") + "]"
        // A thread names its account, so a name comes one time, whatever its case.
        for bad in ["", #"[{"name":"a"}]"#, #"[{"name":"a","folder":"~/.claude"}]"#, #"[{"name":"","folder":"/a"}]"#,
                    #"[{"name":"a","folder":"/a\nb"}]"#, #"[{"name":"Work","folder":"/a"},{"name":"work","folder":"/b"}]"#, tooMany] {
            #expect(SettingTextForm.value(of: bad, as: kind) == nil)
        }
    }
}
