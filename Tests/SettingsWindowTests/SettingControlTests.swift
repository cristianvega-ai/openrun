import AppKit
import Testing
@testable import SettingsWindow

/// The controls of the settings window. Each one shows the text of its
/// setting and tells the new text of a change.
@MainActor @Suite struct SettingControlTests {
    /// The texts that a control told, in order.
    private func changes(of control: any SettingControl) -> () -> [String] {
        let told = Told()
        control.changed = { told.texts.append($0) }
        return { told.texts }
    }

    private final class Told { var texts: [String] = [] }

    @Test func aChoiceShowsItsWordsAndKeepsAValueThatItDoesNotKnow() {
        let control = ChoiceSettingControl([("left", "Left"), ("both", "Both")])
        let told = changes(of: control)
        control.show("both")
        #expect(control.popup.titleOfSelectedItem == "Both")
        control.popup.selectItem(at: 0)
        control.choose()
        // A value of a later build stays in the menu, so the window shows no wrong value.
        control.show("later")
        #expect(control.popup.titleOfSelectedItem == "later" && control.popup.numberOfItems == 3 && told() == ["left"])
    }

    @Test func aFlagIsOnOrOff() {
        let control = FlagSettingControl(title: "Ask")
        let told = changes(of: control)
        control.show("on")
        #expect(control.checkbox.state == .on)
        control.checkbox.state = .off
        control.toggle()
        #expect(told() == ["off"])
    }

    @Test func aNumberStaysInItsRangeAndTellsOnlyAChange() {
        let control = NumberSettingControl(6...72, unit: "points")
        let told = changes(of: control)
        control.show("13")
        #expect(control.field.stringValue == "13" && control.stepper.integerValue == 13)
        for text in ["14", "14", "500", "many", " 6 "] {
            control.field.stringValue = text
            control.typed()
        }
        // The text that is no number goes back to the value before it.
        #expect(told() == ["14", "72", "6"] && control.field.stringValue == "6")
        control.stepper.integerValue = 7
        control.stepped()
        #expect(told().last == "7" && control.field.stringValue == "7")
    }

    @Test func aTextTellsAChangeAndGoesBackWhenItIsEmpty() {
        let control = TextSettingControl(suggestions: ["opus", "sonnet"])
        let told = changes(of: control)
        control.show("opus")
        #expect(control.field is NSComboBox)
        for text in ["  sonnet ", "sonnet", ""] {
            control.field.stringValue = text
            control.typed()
        }
        #expect(told() == ["sonnet"] && control.field.stringValue == "sonnet")
        #expect(!(TextSettingControl(placeholder: "claude").field is NSComboBox))
    }

    @Test func theCommandsAreOneLineOfJSON() {
        let control = EntryListSettingControl()
        let told = changes(of: control)
        control.show(#"[{"command":"","name":"Shell"},{"command":"claude","name":"Claude Code"}]"#)
        #expect(control.table.numberOfRows == 2 && control.entries.map(\.name) == ["Shell", "Claude Code"])
        control.take(row: 1, isName: false, text: "claude --model opus")
        control.take(row: 1, isName: false, text: "claude --model opus")
        control.add()
        control.take(row: 2, isName: true, text: "Monitor")
        control.remove(0)
        control.remove(9)
        #expect(told().count == 4 && told().last == #"[{"command":"claude --model opus","name":"Claude Code"},{"command":"","name":"Monitor"}]"#)
        // Text that is no list changes nothing.
        control.show("{}")
        #expect(control.entries.count == 2)
    }

    @Test func theAccountsAreAListOfNamesAndSettingsFolders() {
        let control = EntryListSettingControl(.settingsFolder)
        let told = changes(of: control)
        control.show(#"[{"folder":"/Users/me/.claude-work","name":"Work"}]"#)
        #expect(control.entries == [.init(name: "Work", detail: "/Users/me/.claude-work")])
        #expect(control.table.tableColumns.map(\.title) == ["Name", "Settings Folder"])
        control.add()
        control.take(row: 1, isName: false, text: "/Users/me/.claude-home")
        #expect(told().last == #"[{"folder":"/Users/me/.claude-work","name":"Work"},{"folder":"/Users/me/.claude-home","name":"New Account"}]"#)
        // The plus button asks for the folder, and a new account gets a name that no other one has.
        var answer: String? = "/Users/me/.claude-third"
        control.chooseDetail = { $0(answer) }
        control.add()
        answer = nil
        control.add()
        #expect(control.entries.map(\.name) == ["Work", "New Account", "New Account 2"] && control.entries.last?.detail == "/Users/me/.claude-third")
        control.remove(2)
        // The commands are no accounts, so they do not show.
        control.show(#"[{"command":"claude","name":"Claude Code"}]"#)
        #expect(control.entries.count == 2)
    }
}
