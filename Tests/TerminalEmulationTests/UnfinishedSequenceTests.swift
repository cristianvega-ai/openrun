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

    /// What `openrun attach` does: it draws the restored screen, writes the
    /// unfinished sequence, and then the output that follows. The terminal
    /// that receives all of it must show what a terminal that received the
    /// whole stream shows, wherever the snapshot fell. The stream has no
    /// hyperlink, because a picture can split one link into two with the same
    /// address, which looks the same but formats differently.
    @Test func aPictureFollowedByTheSequenceAndTheRestShowsTheSameScreen() throws {
        let stream = Array(
            ("héllo \u{1b}[1;38;5;196mwörld\u{1b}[0m \u{1F600}\r\n"
                + "\u{1b}]2;window title\u{7}title set 日本\r\n"
                + "\u{1b}[2;3Hx\u{1b}[4;1H\u{1b}[32mgreen\u{1b}[0m tail").utf8
        )
        let reference = try makeTerminal(columns: 20, rows: 5)
        reference.write(stream)
        let expected = try reference.formatted(.virtualTerminalSequences)

        for cut in 0...stream.count {
            let session = try makeTerminal(columns: 20, rows: 5)
            session.write(Array(stream[..<cut]))
            let restored = try TerminalSnapshot(capturing: session).restoreTerminal(scrollbackLimit: 100)

            let window = try makeTerminal(columns: 20, rows: 5)
            window.write("\u{1b}[H\u{1b}[2J")
            window.write(try restored.formatted(.virtualTerminalSequences))
            window.write(try UnfinishedSequence(of: restored).bytes)
            window.write(Array(stream[cut...]))
            #expect(try window.formatted(.virtualTerminalSequences) == expected, "snapshot at byte \(cut)")
        }
    }
}
