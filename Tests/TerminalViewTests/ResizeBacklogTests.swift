import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct ResizeBacklogTests {
    @Test func aLargeBacklogKeepsItsSizeAndYieldsBeforeTheNextSize() async throws {
        _ = NSApplication.shared
        let initial = TerminalSize(columns: 80, rows: 24)
        let foreign = TerminalSize(columns: 12, rows: 24)
        var earlier = Array("\u{1B}[?1049h".utf8)
        earlier += [UInt8](repeating: 0, count: 16 * 1024 * 1024)
        earlier += Array("\u{1B}[1;70HX".utf8)
        let later = Array("\u{1B}[2;2HY".utf8)
        let reference = try Terminal(size: initial, scrollbackLimit: 10_000)
        reference.write(earlier)
        try reference.resize(to: foreign)
        reference.write(later)
        let expected = try reference.formatted(.plainText)
        let optimistic = try Terminal(size: foreign, scrollbackLimit: 10_000)
        optimistic.write(earlier)
        optimistic.write(later)
        let optimisticScreen = try optimistic.formatted(.plainText)
        try #require(optimisticScreen != expected, "The two size orders must produce different screens.")
        let view = try TerminalView(initialGrid: initial)
        view.waitsForSizeConfirmation = true
        view.write(earlier)
        let started = ContinuousClock.now
        view.followSessionSize(foreign)
        let elapsed = started.duration(to: .now)
        view.write(later)
        #expect(view.gridSize == initial)
        #expect(view.parseTurn(budget: ParseBudget(limit: .zero)))
        #expect(view.gridSize == initial)
        await settle(seconds: 10) { view.gridSize == foreign && (try? view.terminal.formatted(.plainText)) == expected }
        #expect(view.gridSize == foreign)
        #expect(try view.terminal.formatted(.plainText) == expected)
        print("resize-backlog: \(earlier.count) earlier bytes; size request took \(elapsed); the first zero-budget turn retained the old size")
    }
}
