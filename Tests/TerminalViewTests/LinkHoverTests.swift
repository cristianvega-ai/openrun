import AppKit
import TerminalEmulation
import TerminalRendering
import Testing
@testable import TerminalView

@MainActor @Suite struct LinkHoverTests {
    private func cell(_ column: UInt16, _ row: UInt32 = 0) -> ViewportCell { ViewportCell(column: column, row: row) }

    @Test func commandOverAnAddressGivesItsUnderlineAndAHand() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 3), scrollbackLimit: 0)
        terminal.write("go https://a.b/c \u{1B}]8;;https://d.e\u{07}osc\u{1B}]8;;\u{07}")
        let hover = LinkHover(terminal: terminal)
        #expect(!hover.update(modifiers: [], at: cell(5)) && hover.link == nil && !hover.isActive)
        #expect(hover.update(modifiers: .command, at: cell(5)) && hover.isOverLink)
        #expect(hover.link?.runs == [ViewportCellRun(row: 0, columns: 3..<16)])
        // Another cell of the same address changes nothing.
        #expect(!hover.update(modifiers: .command, at: cell(9)))
        // A link of OSC 8 shows the hand with no underline.
        #expect(hover.update(modifiers: .command, at: cell(18)) && hover.isOverLink && hover.link == nil)
        #expect(hover.update(modifiers: .command, at: cell(0)) && !hover.isOverLink)
        #expect(hover.update(modifiers: .command, at: cell(5)))
        #expect(hover.update(modifiers: [], at: cell(5)) && hover.link == nil && !hover.isOverLink && !hover.isActive)
    }

    @Test func newTextUnderTheSameCellIsReadAgain() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 3), scrollbackLimit: 0)
        terminal.write("https://a.b")
        let hover = LinkHover(terminal: terminal)
        #expect(hover.update(modifiers: .command, at: cell(2)))
        terminal.write("\r\u{1B}[Kplain text")
        #expect(!hover.update(modifiers: .command, at: cell(2)) && hover.link != nil)
        #expect(hover.update(modifiers: .command, at: cell(2), textChanged: true) && hover.link == nil)
    }
}
