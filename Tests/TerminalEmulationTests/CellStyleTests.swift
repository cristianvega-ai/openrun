import Testing
@testable import TerminalEmulation

@Suite struct CellStyleTests {
    @Test func attributesReachTheCell() throws {
        let row = try RenderCellTests().cells(of: "\u{1B}[1;3;9ma\u{1B}[4:3mb\u{1B}[0mc")
        #expect(row[0].style.isBold && row[0].style.isItalic && row[0].style.isStruckThrough)
        #expect(row[1].style.underline == .curly)
        #expect(row[2].style == CellStyle())
    }

    @Test func colorsResolveThroughThePalette() throws {
        let row = try RenderCellTests().cells(of: "\u{1B}[31ma\u{1B}[48;2;1;2;3mb\u{1B}[0m\u{1B}[44m \u{1B}[0mc")
        #expect(row[0].foreground != nil)
        #expect(row[1].background == TerminalColor(red: 1, green: 2, blue: 3))
        #expect(row[2].background != nil && row[3].background == nil && row[3].foreground == nil)
    }
}
