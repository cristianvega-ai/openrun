import AppKit
import Testing
@testable import SettingsWindow

/// One entry of a list setting.
@MainActor @Suite struct EntryRowViewTests {
    @Test func aRowTellsTheNewTextOfAFieldAndThePressOfAButton() {
        let row = EntryRowView(name: "Claude Code", detail: "claude", placeholder: "Login shell", isFolder: false)
        var told: [String] = []
        row.edited = { told.append(($0 ? "name " : "command ") + $1) }
        row.remove = { told.append("remove") }
        row.nameField.stringValue = "Agent"
        row.typed(row.nameField)
        row.detailField.stringValue = "claude --model opus"
        row.typed(row.detailField)
        row.removeEntry()
        #expect(told == ["name Agent", "command claude --model opus", "remove"])
        #expect(row.detailField.isEditable && row.detailField.placeholderString == "Login shell")
        // The folder of an account is a label with the full path as its help. A button asks for another folder.
        let account = EntryRowView(name: "Work", detail: "/Users/me/.claude-work", placeholder: "", isFolder: true)
        account.choose = { told.append("choose") }
        account.chooseDetail()
        #expect(!account.detailField.isEditable && account.detailField.toolTip == "/Users/me/.claude-work" && told.last == "choose")
        #expect(account.arrangedSubviews.count == row.arrangedSubviews.count + 1)
    }
}
