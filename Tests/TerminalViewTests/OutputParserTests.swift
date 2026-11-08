import Testing
import TerminalEmulation
import Synchronization
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

    @Test func admissionEndsOnlyAfterTheWholeOutputIsParsedOrDiscarded() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 2), scrollbackLimit: 0)
        let parser = OutputParser(pieceSize: 2)
        let finished = Mutex<[Int]>([])
        parser.append(Array("abcde".utf8)) { finished.withLock { $0.append(1) } }
        parser.append(Array("fg".utf8)) { finished.withLock { $0.append(2) } }
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(finished.withLock { $0.isEmpty })
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(finished.withLock { $0 } == [1])
        parser.discard()
        #expect(finished.withLock { $0 } == [1, 2])
        #expect(!parser.hasPendingOutput)
        #expect(try screen(terminal) == "abcde")
    }

    @Test func sizeAdmissionEndsAfterTheSizeIsApplied() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 2), scrollbackLimit: 0)
        let parser = OutputParser()
        let order = Mutex<[String]>([])
        parser.onSize = { _, _, _ in order.withLock { $0.append("applied") } }
        parser.append(size: TerminalSize(columns: 10, rows: 2), tellsDelegate: false) {
            order.withLock { $0.append("completed") }
        }
        #expect(!parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(order.withLock { $0 } == ["applied", "completed"])
    }

    @Test func aCloseDuringASizeCallbackReleasesEachEventOnce() throws {
        let terminal = try Terminal(size: TerminalSize(columns: 20, rows: 2), scrollbackLimit: 0)
        let parser = OutputParser()
        let finished = Mutex(0)
        parser.onSize = { _, _, _ in parser.discard() }
        parser.append(size: TerminalSize(columns: 10, rows: 2), tellsDelegate: false) { finished.withLock { $0 += 1 } }
        parser.append(Array("later".utf8)) { finished.withLock { $0 += 1 } }
        #expect(!parser.parse(into: terminal, budget: ParseBudget(limit: .seconds(60))))
        #expect(finished.withLock { $0 == 2 })
        #expect(try screen(terminal).isEmpty)
    }

    @Test func aSizeWaitsForEarlierOutputAndPrecedesLaterOutput() throws {
        let initial = TerminalSize(columns: 8, rows: 3)
        let changed = TerminalSize(columns: 4, rows: 3)
        let terminal = try Terminal(size: initial, scrollbackLimit: 10)
        let parser = OutputParser(pieceSize: 4)
        parser.append(Array("abcdefghi".utf8))
        parser.append(size: changed, tellsDelegate: false)
        parser.append(Array("jklm".utf8))
        parser.append(size: initial, tellsDelegate: true)
        var applied: [TerminalSize] = [], delegateFlags: [Bool] = []
        parser.onSize = { size, tellsDelegate, _ in
            try? terminal.resize(to: size)
            applied.append(size)
            delegateFlags.append(tellsDelegate)
        }
        for _ in 0..<3 {
            #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
            #expect(terminal.size == initial && applied.isEmpty)
        }
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(terminal.size == changed && applied == [changed])
        #expect(parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(!parser.parse(into: terminal, budget: ParseBudget(limit: .zero)))
        #expect(terminal.size == initial && applied == [changed, initial] && delegateFlags == [false, true])
        let reference = try Terminal(size: initial, scrollbackLimit: 10)
        reference.write("abcdefghi")
        try reference.resize(to: changed)
        reference.write("jklm")
        try reference.resize(to: initial)
        #expect(try terminal.formatted(.plainText) == reference.formatted(.plainText))
    }
}
