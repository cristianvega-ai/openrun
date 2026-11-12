import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct MenuItemValidationTests {
    /// OSC 52: an editor over ssh copies text for the user.
    @Test func aProgramPutsTextOnThePasteboardOfTheView() throws {
        let view = try TerminalView()
        let pasteboard = FakePasteboard()
        view.pasteboard = pasteboard
        var isApplied = false
        view.write(Array("\u{1B}]52;c;aGVsbG8=\u{07}".utf8))
        view.afterPendingOutput { isApplied = true }
        wait(seconds: 5) { isApplied }
        #expect(pasteboard.text == "hello" && pasteboard.plainTextReads == 0)
    }

    @Test func copyNeedsASelectionAndPasteNeedsText() throws {
        let view = try TerminalView()
        let board = FakePasteboard()
        view.pasteboard = board
        let copy = NSMenuItem(title: "Copy", action: #selector(TerminalView.copy(_:)), keyEquivalent: "c")
        let paste = NSMenuItem(title: "Paste", action: #selector(TerminalView.paste(_:)), keyEquivalent: "v")
        #expect(!view.validateMenuItem(copy) && !view.validateMenuItem(paste))
        view.terminal.write("word")
        try view.terminal.selectWord(at: ViewportCell(column: 1, row: 0))
        board.text = "text"
        #expect(view.validateMenuItem(copy) && view.validateMenuItem(paste))
        board.text = nil
        view.terminal.clearSelection()
        #expect(!view.validateMenuItem(copy) && !view.validateMenuItem(paste))
        #expect(board.plainTextReads == 0)
    }

    @Test func selectAllSelectsTheScrollbackAndTheScreenForCopy() throws {
        let view = try TerminalView(initialGrid: TerminalSize(columns: 10, rows: 2))
        let board = FakePasteboard()
        view.pasteboard = board
        view.terminal.write("first\r\nsecond\r\nthird")
        #expect(view.validateMenuItem(NSMenuItem(title: "Select All", action: #selector(TerminalView.selectAll(_:)), keyEquivalent: "a")))
        view.selectAll(nil)
        view.copy(nil)
        #expect(board.text == "first\nsecond\nthird")
    }

    @Test func theSystemPasteboardReportsTextFromItsTypes() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let board = GeneralPasteboard(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(Data([0]), forType: .png)
        #expect(!board.hasPlainText)
        pasteboard.clearContents()
        pasteboard.setString("text", forType: .string)
        #expect(board.hasPlainText)
    }
}
