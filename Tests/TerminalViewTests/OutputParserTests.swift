import Testing
import TerminalEmulation
@testable import TerminalView

@Suite struct OutputParserTests {
    private func screen(_ terminal: Terminal) throws -> String {
        String(decoding: try terminal.formatted(.plainText), as: UTF8.self)
    }

    @Test func aBudgetOfNoTimeParsesOnePieceForEachTurn() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 2), scrollbackLimit: 0)
        let parser = OutputParser(pieceSize: 4)
        parser.append(Array("abcdefghij".utf8))
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(try screen(terminal) == "abcd")
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(!parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(try screen(terminal) == "abcdefghij")
    }

    @Test func aLongBudgetParsesAllOutputInOneTurn() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 2), scrollbackLimit: 0)
        let parser = OutputParser(pieceSize: 3)
        parser.append(Array("abcdefghij".utf8))
        #expect(!parser.parse(into: terminal, budget: ParseBudget(limit: .seconds(60))))
        #expect(!parser.hasPendingOutput)
        #expect(try screen(terminal) == "abcdefghij")
    }

    @Test func aCharacterThatSplitsBetweenPiecesComesOutWhole() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 2), scrollbackLimit: 0)
        let parser = OutputParser(pieceSize: 1)
        parser.append(Array("日本".utf8))
        #expect(!parser.parse(into: terminal, budget: ParseBudget(limit: .seconds(60))))
        #expect(try screen(terminal) == "日本")
    }
}
