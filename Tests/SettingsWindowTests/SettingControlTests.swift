import AccountUsage
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
        // A long name, such as one of a font, leaves the room of the words of its row.
        control.show(String(repeating: "A Font With a Long Name ", count: 4))
        #expect(control.popup.fittingSize.width <= 240 && TextSettingControl().field.fittingSize.width == 220)
    }

    @Test func theSegmentsShowEachChoiceAtOnce() {
        let control = SegmentSettingControl([("left", "Left"), ("both", "Both"), ("neither", "Neither")])
        let told = changes(of: control)
        control.show("both")
        #expect(control.segments.segmentCount == 3 && control.segments.label(forSegment: 2) == "Neither" && control.segments.selectedSegment == 1)
        control.segments.selectedSegment = 2
        control.choose()
        // A value of a later build selects no segment, so the window shows no wrong value.
        control.show("later")
        #expect(control.segments.selectedSegment == -1 && told() == ["neither"])
    }

    @Test func aFlagIsASwitchThatIsOnOrOff() {
        let control = FlagSettingControl()
        let told = changes(of: control)
        control.show("on")
        #expect(control.toggle.state == .on && !control.isWide)
        control.toggle.state = .off
        control.toggled()
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
        #expect(control.entryRows.map(\.nameField.stringValue) == ["Shell", "Claude Code"] && control.entries.map(\.name) == ["Shell", "Claude Code"])
        // Each entry is a row of two fields, and the last row adds an entry.
        let rows = try? #require(control.view as? SettingRowsView).rows
        #expect(rows?.count == 3 && control.isWide && control.entryRows[0].detailField.placeholderString == "Login shell" && control.entryRows[1].detailField.isEditable)
        control.entryRows[1].detailField.stringValue = "claude --model opus"
        control.entryRows[1].typed(control.entryRows[1].detailField)
        control.take(row: 1, isName: false, text: "claude --model opus")
        // The same list keeps its rows, so a field that the user types in keeps the keyboard.
        let kept = control.entryRows[1]
        control.show(#"[{"command":"","name":"Shell"},{"command":"claude --model opus","name":"Claude Code"}]"#)
        #expect(control.entryRows[1] === kept)
        control.addButton.performClick(nil)
        control.take(row: 2, isName: true, text: "Monitor")
        control.entryRows[0].removeEntry()
        control.remove(9)
        #expect(told().count == 4 && told().last == #"[{"command":"claude --model opus","name":"Claude Code"},{"command":"","name":"Monitor"}]"#)
        // Text that is no list changes nothing.
        control.show("{}")
        #expect(control.entries.count == 2 && control.addButton.title == "Add Command")
    }

    @Test func theAccountsAreRowsWithANameAndASettingsFolder() {
        let control = EntryListSettingControl(.account(program: "claude", agent: "claude-code"))
        let told = changes(of: control)
        control.show(#"[{"folder":"/Users/me/.claude-work","name":"Work"}]"#)
        #expect(control.entries == [.init(name: "Work", detail: "/Users/me/.claude-work")])
        // The first row is the login of the shell, which is no entry. The folder of an account is a label.
        let rows = (control.view as? SettingRowsView)?.rows ?? []
        #expect(rows.count == 3 && (rows.first as? SettingRowView)?.label?.stringValue == "Login of Your Shell")
        #expect((rows.first as? SettingRowView)?.note?.stringValue.contains("the claude command") == true)
        #expect(!control.entryRows[0].detailField.isEditable && control.entryRows[0].detailField.toolTip == "/Users/me/.claude-work")
        control.add()
        control.take(row: 1, isName: false, text: "/Users/me/.claude-home")
        #expect(told().last == #"[{"folder":"/Users/me/.claude-work","name":"Work"},{"folder":"/Users/me/.claude-home","name":"New Account"}]"#)
        // The button asks for the folder. A new account takes its name from the folder, and no two accounts share a name.
        var answer: String? = "/Users/me/.claude-team-two"
        control.chooseDetail = { $0(answer) }
        control.add()
        control.addButton.performClick(nil)
        answer = nil
        control.add()
        #expect(control.entries.map(\.name) == ["Work", "New Account", "Team Two", "Team Two 2"] && control.entries.last?.detail == "/Users/me/.claude-team-two")
        // The button of a row asks for another folder.
        answer = "/Users/me/.claude-office"
        control.entryRows[0].chooseDetail()
        #expect(control.entries[0] == .init(name: "Work", detail: "/Users/me/.claude-office") && control.entryRows[0].detailField.toolTip == "/Users/me/.claude-office")
        control.remove(3)
        // The commands are no accounts, so they do not show.
        control.show(#"[{"command":"claude","name":"Claude Code"}]"#)
        #expect(control.entries.count == 3)
    }

    @Test func eachAccountShowsItsUsageUnderItsName() {
        let control = EntryListSettingControl(.account(program: "claude", agent: "claude-code"))
        control.show(#"[{"folder":"/Users/me/.claude-work","name":"Work"},{"folder":"/Users/me/.claude-home","name":"Home"}]"#)
        #expect(control.usageLines.count == 3 && control.usageLines.allSatisfy { $0.display == nil } && EntryListSettingControl().usageLines.isEmpty)
        let work = AccountUsageDisplay(title: "Claude Code · Work", windows: [.init(name: "Week", usedFraction: 0.4)], readTime: "09:15", help: "", agent: "claude-code", account: "Work")
        let shell = AccountUsageDisplay(title: "Claude Code", windows: [], readTime: "08:00", help: "", agent: "claude-code")
        // A reading of another agent with the same name of an account does not show.
        control.showUsage([work, shell, AccountUsageDisplay(title: "Codex · Home", windows: [], readTime: "", help: "", agent: "codex", account: "Home")])
        #expect(control.usageLines.map(\.display) == [shell, work, nil])
        // New rows keep the readings.
        control.remove(1)
        #expect(control.usageLines.map(\.display) == [shell, work])
    }
}
