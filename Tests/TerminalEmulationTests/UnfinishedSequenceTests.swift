import Testing
@testable import TerminalEmulation

@Suite struct UnfinishedSequenceTests {
    @Test func aTerminalBetweenSequencesHasNone() throws {
        let terminal = try makeTerminal()
        #expect(try UnfinishedSequence(of: terminal).bytes.isEmpty)
        terminal.write("plain \u{1b}[31mred\u{1b}[0m text")
        #expect(try UnfinishedSequence(of: terminal).bytes.isEmpty)
    }

    @Test(arguments: [
        "\u{1b}",
        "\u{1b}[3",
        "\u{1b}[?10",
        "\u{1b}]0;title without end",
        "\u{1b}Pzdevice string",
        "\u{1b}_Gapplication string",
    ])
    func theStartOfASequenceIsKept(start: String) throws {
        let terminal = try makeTerminal()
        terminal.write("before ")
        terminal.write(start)
        #expect(try UnfinishedSequence(of: terminal).bytes == Array(start.utf8))
    }

    @Test func theStartOfAMultibyteCharacterIsKept() throws {
        let euro = Array("\u{20AC}".utf8)
        let terminal = try makeTerminal()
        terminal.write(Array("a".utf8) + euro.prefix(2))
        #expect(try UnfinishedSequence(of: terminal).bytes == Array(euro.prefix(2)))
    }

    @Test func aRestoredTerminalKeepsTheSequenceOfItsSnapshot() throws {
        let terminal = try makeTerminal()
        terminal.write("before \u{1b}[3")
        let restored = try TerminalSnapshot(capturing: terminal).restoreTerminal(scrollbackLimit: 100)
        #expect(try UnfinishedSequence(of: restored).bytes == Array("\u{1b}[3".utf8))
        restored.write("1mred")
        #expect(try UnfinishedSequence(of: restored).bytes.isEmpty)
    }

}
