import Testing
@testable import TerminalEmulation

@Suite struct SelectionGestureTests {
    private func click(_ gesture: SelectionGesture, at milliseconds: UInt64) throws {
        let cell = ViewportCell(column: 5, row: 0)
        try gesture.press(at: cell, pixel: (x: 45, y: 8), timeInNanoseconds: milliseconds * 1_000_000, repeatIntervalInNanoseconds: 500_000_000)
        try gesture.release(at: cell)
    }

    @Test func quickClicksSelectAWordAndThenTheLineButSlowOnesDoNot() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write("one two three")
        let gesture = try SelectionGesture(for: terminal)
        try click(gesture, at: 0)
        #expect(gesture.clickCount == 1 && !terminal.hasSelection)
        try click(gesture, at: 100)
        #expect(gesture.clickCount == 2 && terminal.selectedText() == "two")
        try click(gesture, at: 200)
        #expect(gesture.clickCount == 3 && terminal.selectedText() == "one two three")
        try click(gesture, at: 3000)
        #expect(gesture.clickCount == 1)
    }
}
