import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct MenuItemValidationTests {
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
