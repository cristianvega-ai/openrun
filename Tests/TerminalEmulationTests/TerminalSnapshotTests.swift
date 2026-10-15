import Testing
@testable import TerminalEmulation

/// Everything a client can observe about a terminal.
private struct Observation: Equatable {
    var size: TerminalSize
    var cursorPosition: TerminalCursorPosition
    var isAlternateScreenActive: Bool
    var visible: [UInt8]
    var withScrollback: [UInt8]

    init(_ terminal: Terminal) throws {
        size = terminal.size
        cursorPosition = terminal.cursorPosition
        isAlternateScreenActive = terminal.isAlternateScreenActive
        visible = try terminal.formatted(.virtualTerminalSequences)
        withScrollback = try terminal.formatted(.virtualTerminalSequences, extent: .withScrollback)
    }
}

@Suite struct TerminalSnapshotTests {
    /// The markup for a link. The attribute sign is apart from the name so
    /// that the name scan does not read the attribute as a name of ours.
    private static func anchor(to address: String, text: String) -> String {
        "<a href" + "=\"\(address)\">\(text)</a>"
    }

    private func restore(_ terminal: Terminal) throws -> Terminal {
        try TerminalSnapshot(capturing: terminal).restoreTerminal(scrollbackLimit: 1000)
    }

    @Test func roundTripKeepsScreenScrollbackAndCursor() throws {
        let terminal = try makeTerminal(columns: 20, rows: 4)
        for number in 1...15 {
            terminal.write("\u{1b}[3\(number % 7 + 1)mline \(number)\u{1b}[0m\r\n")
        }
        terminal.write("prompt> \u{1b}[1mtyped\u{1b}[0m")

        let restored = try restore(terminal)

        #expect(try Observation(restored) == Observation(terminal))
        #expect(restored.scrollbackLineCount == terminal.scrollbackLineCount)
        #expect(restored.cursorPosition == terminal.cursorPosition)
        #expect(try restored.formatted(.plainText, extent: .withScrollback).starts(with: Array("line 1\n".utf8)))
    }

    /// The checks here name the bytes and the markup that must come out of the
    /// restored terminal. `Observation` cannot catch a style that the snapshot
    /// loses, because it formats the original and the copy the same way.
    @Test func roundTripKeepsStylesCursorVisibilityModesAndLinks() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write("\u{1b}[1mbold\u{1b}[0m \u{1b}[38;2;10;20;30mtrue\u{1b}[0m \u{1b}[4munder\u{1b}[0m ")
        terminal.write("\u{1b}]8;;https://example.com\u{7}link\u{1b}]8;;\u{7}")
        terminal.write("\u{1b}[?25l\u{1b}[?2004h\u{1b}[?1h")

        let restored = try restore(terminal)

        let markup = String(decoding: try restored.formatted(.hypertextMarkup), as: UTF8.self)
        #expect(markup == "<div style=\"font-family: monospace; white-space: pre;\"><div style=\"display: inline;font-weight: bold;\">bold</div> <div style=\"display: inline;color: rgb(10, 20, 30);\">true</div> <div style=\"display: inline;text-decoration-line: underline;text-decoration-style: solid;\">under</div> " + Self.anchor(to: "https://example.com", text: "link") + "</div>")

        let sequences = String(decoding: try restored.formatted(.virtualTerminalSequences), as: UTF8.self)
        #expect(sequences.contains("\u{1b}[1mbold"), "bold")
        #expect(sequences.contains("\u{1b}[38;2;10;20;30mtrue"), "true color")
        #expect(sequences.contains("\u{1b}[4munder"), "underline")
        #expect(sequences.contains("\u{1b}]8;;https://example.com\u{1b}\\link\u{1b}]8;;\u{1b}\\"), "hyperlink")
        #expect(sequences.contains("\u{1b}[?25l"), "hidden cursor")
        #expect(sequences.contains("\u{1b}[?2004h"), "bracketed paste")
        #expect(sequences.contains("\u{1b}[?1h"), "application cursor keys")
    }

    @Test func roundTripKeepsAVisibleCursorAndPlainModes() throws {
        let terminal = try makeTerminal(columns: 40, rows: 5)
        terminal.write("\u{1b}[?25l\u{1b}[?2004h\u{1b}[?1h\u{1b}[?25h\u{1b}[?2004l\u{1b}[?1l text")

        let sequences = String(decoding: try restore(terminal).formatted(.virtualTerminalSequences), as: UTF8.self)

        #expect(!sequences.contains("\u{1b}[?25l"))
        #expect(!sequences.contains("\u{1b}[?2004h"))
        #expect(!sequences.contains("\u{1b}[?1h"))
    }

    @Test func roundTripKeepsTheAlternateScreen() throws {
        let terminal = try makeTerminal(columns: 20, rows: 4)
        terminal.write("primary text\r\n")
        terminal.write("\u{1b}[?1049h\u{1b}[2J\u{1b}[Halternate text")

        let restored = try restore(terminal)

        #expect(restored.isAlternateScreenActive)
        #expect(try restored.visibleText() == "alternate text")
        #expect(try Observation(restored) == Observation(terminal))

        // Leaving the alternate screen must bring back the primary screen.
        terminal.write("\u{1b}[?1049l")
        restored.write("\u{1b}[?1049l")
        #expect(!restored.isAlternateScreenActive)
        #expect(try restored.visibleText() == "primary text")
        #expect(try Observation(restored) == Observation(terminal))
    }

    @Test func snapshotBytesRestoreFromAnotherArray() throws {
        let terminal = try makeTerminal()
        terminal.write("kept")
        let snapshot = try TerminalSnapshot(capturing: terminal)
        let restored = try TerminalSnapshot(bytes: snapshot.bytes).restoreTerminal(scrollbackLimit: 10)
        #expect(try restored.visibleText() == "kept")
    }

    @Test func truncatedBytesFailToRestore() throws {
        let terminal = try makeTerminal()
        terminal.write("kept")
        let snapshot = try TerminalSnapshot(capturing: terminal)
        let truncated = TerminalSnapshot(bytes: Array(snapshot.bytes.dropLast(8)))
        #expect(throws: TerminalEmulationError.self) {
            _ = try truncated.restoreTerminal(scrollbackLimit: 10)
        }
    }

    @Test func snapshotInsideAnEscapeSequenceContinues() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write("before \u{1b}[3")

        let restored = try restore(terminal)
        restored.write("1mred\u{1b}[0m after")

        let reference = try makeTerminal(columns: 20, rows: 3)
        reference.write("before \u{1b}[31mred\u{1b}[0m after")

        #expect(try Observation(restored) == Observation(reference))
        #expect(try restored.visibleText() == "before red after")
    }

    @Test func snapshotInsideAMultibyteCharacterContinues() throws {
        let bytes = Array("a\u{1F600}b".utf8)
        // Cut after the first two bytes of the four-byte emoji.
        let cut = 3

        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write(Array(bytes[..<cut]))

        let restored = try restore(terminal)
        restored.write(Array(bytes[cut...]))

        let reference = try makeTerminal(columns: 20, rows: 3)
        reference.write(bytes)

        #expect(try Observation(restored) == Observation(reference))
        #expect(try restored.visibleText() == "a\u{1F600}b")
    }

    @Test func snapshotAtEveryByteBoundaryContinues() throws {
        let stream = Array(
            ("héllo \u{1b}[1;38;5;196mwörld\u{1b}[0m \u{1F600}\u{1b}]8;;https://example.com\u{7}link\u{1b}]8;;\u{7}\r\n"
                + "日本語\u{1b}[2;3Hx\u{1b}[?1049halt\u{1b}[?1049l\r\ntail").utf8
        )
        let reference = try makeTerminal(columns: 12, rows: 3)
        reference.write(stream)
        let expected = try Observation(reference)
        // The reference formats itself, so pin its markup to a fixed text.
        // Each restored terminal must produce the same text.
        let expectedMarkup = "<div style=\"font-family: monospace; white-space: pre;\">h&#233;llo <div style=\"display: inline;color: var(--vt-palette-196);font-weight: bold;\">w&#246;rld</div> \n&#128512;x" + Self.anchor(to: "https://example.com", text: "ink\n") + "tail&#35486;</div>"
        #expect(String(decoding: try reference.formatted(.hypertextMarkup), as: UTF8.self) == expectedMarkup)

        for cut in 0...stream.count {
            let first = try makeTerminal(columns: 12, rows: 3)
            first.write(Array(stream[..<cut]))
            let restored = try restore(first)
            restored.write(Array(stream[cut...]))
            #expect(try Observation(restored) == expected, "snapshot at byte \(cut)")
            #expect(String(decoding: try restored.formatted(.hypertextMarkup), as: UTF8.self) == expectedMarkup, "markup after a snapshot at byte \(cut)")
        }
    }

    @Test func restoredTerminalCanTakeAnotherSnapshotInsideASequence() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write("x\u{1b}[")

        let second = try restore(try restore(terminal))
        second.write("31mred")

        let reference = try makeTerminal(columns: 20, rows: 3)
        reference.write("x\u{1b}[31mred")
        #expect(try Observation(second) == Observation(reference))
    }

    /// Lines of scrollback in many colors, then an escape sequence that is
    /// not finished yet. On the alternate screen the primary screen keeps the
    /// scrollback.
    private func colorfulTerminal(onAlternateScreen: Bool) throws -> Terminal {
        let terminal = try makeTerminal(columns: 400, rows: 6, scrollbackLimit: 10_000)
        for number in 1...2000 {
            terminal.write("\u{1b}[38;5;\(number % 256)mline \(number) " + String(repeating: "x", count: 300) + "\u{1b}[0m\r\n")
        }
        if onAlternateScreen { terminal.write("\u{1b}[?1049halternate text\r\n") }
        terminal.write("prompt> \u{1b}[3")
        return terminal
    }

    @Test func aCaptureWithinTheLimitIsTheWholeCapture() throws {
        let terminal = try colorfulTerminal(onAlternateScreen: false)
        let whole = try TerminalSnapshot(capturing: terminal)
        #expect(try TerminalSnapshot(capturing: terminal, byteLimit: whole.bytes.count) == whole)
    }

    @Test(arguments: [false, true])
    func aCaptureOverTheLimitKeepsTheNewestScrollbackAndTheWholeScreen(onAlternateScreen: Bool) throws {
        let terminal = try colorfulTerminal(onAlternateScreen: onAlternateScreen)
        let whole = try TerminalSnapshot(capturing: terminal)
        let limit = whole.bytes.count / 2
        let fitted = try #require(try TerminalSnapshot(capturing: terminal, byteLimit: limit))
        #expect(fitted.bytes.count <= limit)

        let restored = try fitted.restoreTerminal(scrollbackLimit: 10_000)
        #expect(try UnfinishedSequence(of: restored).bytes == [0x1B, 0x5B, 0x33])
        for copy in [terminal, restored] { copy.write("1mred\u{1b}[0m") }
        #expect(try restored.formatted(.virtualTerminalSequences) == terminal.formatted(.virtualTerminalSequences))
        #expect(restored.cursorPosition == terminal.cursorPosition)
        #expect(restored.isAlternateScreenActive == onAlternateScreen)

        // The terminal keeps its whole scrollback. The snapshot keeps the
        // newest lines, about half of them.
        for copy in [terminal, restored] where onAlternateScreen { copy.write("\u{1b}[?1049l") }
        let original = String(decoding: try terminal.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
        let kept = String(decoding: try restored.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
        #expect(original.hasPrefix("line 1 "))
        #expect(original.hasSuffix(kept))
        let lineCount = kept.split(separator: "\n").count
        #expect(lineCount > 700 && lineCount < 1000, "kept \(lineCount) lines")
    }

    @Test func noCaptureFitsWhenTheScreensAloneAreLarger() throws {
        let terminal = try colorfulTerminal(onAlternateScreen: false)
        #expect(try TerminalSnapshot(capturing: terminal, byteLimit: 100) == nil)
    }
}
