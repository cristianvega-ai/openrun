import Testing
@testable import TerminalEmulation

@Suite struct RenderCellTests {
    func cells(of text: String) throws -> [RenderCell] {
        let terminal = try makeTerminal(columns: 10, rows: 2)
        let state = try RenderState()
        terminal.write(text)
        try state.update(from: terminal)
        var result: [RenderCell] = []
        try state.forEachRow(onlyChanged: false) { row in
            if row.viewportRow == 0 { try row.forEachCell(palette: state.colors.palette) { result.append($0) } }
        }
        return result
    }

    @Test func wideCharacterTakesACellAndATail() throws {
        let row = try cells(of: "a日x")
        #expect(row.prefix(5).map(\.text) == ["a", "日", "", "x", ""])
        #expect(row.prefix(4).map(\.width) == [.narrow, .wide, .wideTail, .narrow])
    }

    @Test func combiningMarkJoinsTheCluster() throws {
        let cell = try cells(of: "e\u{0301}")[0]
        #expect(cell.base == "e" && cell.extraScalars == ["\u{0301}"])
    }

    @Test func cellsOfALinkSaySo() throws {
        let row = try cells(of: "\u{1B}]8;;https://example.com\u{07}a\u{1B}]8;;\u{07}b")
        #expect(row.prefix(2).map(\.hasHyperlink) == [true, false])
    }
}
