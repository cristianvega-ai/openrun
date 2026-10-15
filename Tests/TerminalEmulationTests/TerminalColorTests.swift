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
}
