import Testing
@testable import TerminalEmulation

@Suite struct TerminalColorTests {
    private let red = TerminalColor(red: 255, green: 0, blue: 0)
    private let blue = TerminalColor(red: 0, green: 0, blue: 255)

    /// A restored terminal, as a client makes it. The session process had a
    /// handler and the dark appearance, so the snapshot holds white on black.
    private func restoredTerminal() throws -> Terminal {
        let original = try makeTerminal()
        try original.setReplyHandler({ _ in }, colorScheme: { .dark })
        original.write("text")
        return try TerminalSnapshot(capturing: original).restoreTerminal(scrollbackLimit: 1000)
    }

    @Test func aNewTerminalHasNoDefaultColors() throws {
        let terminal = try makeTerminal()
        #expect(terminal.defaultForegroundColor == nil)
        #expect(terminal.defaultBackgroundColor == nil)
        #expect(terminal.defaultCursorColor == nil)
    }

    @Test func aRestoredTerminalKeepsTheDefaultsOfTheSessionProcess() throws {
        let restored = try restoredTerminal()
        #expect(restored.defaultForegroundColor == TerminalColor(red: 255, green: 255, blue: 255))
        #expect(restored.defaultBackgroundColor == TerminalColor(red: 0, green: 0, blue: 0))
    }

    @Test func aRestoredTerminalTakesNewDefaultColors() throws {
        let restored = try restoredTerminal()
        #expect(!restored.hasReplyHandler)
        try restored.setDefaultForegroundColor(red)
        try restored.setDefaultBackgroundColor(blue)
        try restored.setDefaultCursorColor(red)
        #expect(restored.defaultForegroundColor == red)
        #expect(restored.defaultBackgroundColor == blue)
        #expect(restored.defaultCursorColor == red)
    }

    @Test func aNilColorClearsTheDefault() throws {
        let restored = try restoredTerminal()
        try restored.setDefaultCursorColor(red)
        try restored.setDefaultForegroundColor(nil)
        try restored.setDefaultBackgroundColor(nil)
        try restored.setDefaultCursorColor(nil)
        #expect(restored.defaultForegroundColor == nil)
        #expect(restored.defaultBackgroundColor == nil)
        #expect(restored.defaultCursorColor == nil)
    }

    @Test func aRestoredTerminalTakesANewDefaultPalette() throws {
        let restored = try restoredTerminal()
        let builtIn = restored.defaultPalette
        #expect(builtIn.count == 256)
        try restored.setDefaultPalette(Array(repeating: red, count: 256))
        #expect(restored.defaultPalette == Array(repeating: red, count: 256))
        try restored.setDefaultPalette(nil)
        #expect(restored.defaultPalette == builtIn)
    }

    @Test func aPaletteOfTheWrongLengthIsRefused() throws {
        let terminal = try makeTerminal()
        let before = terminal.defaultPalette
        #expect(throws: TerminalEmulationError.self) { try terminal.setDefaultPalette([red]) }
        #expect(terminal.defaultPalette == before)
    }

    @Test func colorsThatAProgramSetsSurviveANewDefault() throws {
        let terminal = try makeTerminal()
        var replies: [[UInt8]] = []
        try terminal.setReplyHandler({ replies.append($0) }, colorScheme: { .light })
        terminal.write("\u{1B}]11;rgb:ff/00/00\u{07}\u{1B}]4;1;rgb:00/ff/00\u{07}")

        try terminal.setDefaultBackgroundColor(blue)
        try terminal.setDefaultPalette(Array(repeating: blue, count: 256))
        terminal.write("\u{1B}]11;?\u{07}\u{1B}]4;1;?\u{07}\u{1B}]4;2;?\u{07}")
        let text = replies.map { String(decoding: $0, as: UTF8.self) }
        #expect(text == [
            "\u{1B}]11;rgb:ffff/0000/0000\u{07}",
            "\u{1B}]4;1;rgb:0000/ffff/0000\u{07}",
            "\u{1B}]4;2;rgb:0000/0000/ffff\u{07}",
        ])
        // The program color is not the default, so the default reads back.
        #expect(terminal.defaultBackgroundColor == blue)

        // When the program resets its color, the new default shows.
        replies.removeAll()
        terminal.write("\u{1B}]111\u{07}\u{1B}]11;?\u{07}")
        #expect(replies.map { String(decoding: $0, as: UTF8.self) } == ["\u{1B}]11;rgb:0000/0000/ffff\u{07}"])
    }
}
