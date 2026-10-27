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

    @Test func aDragSelectsFromThePressToThePointer() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write("one two three")
        let gesture = try SelectionGesture(for: terminal)
        try gesture.press(at: ViewportCell(column: 4, row: 0), pixel: (x: 36, y: 8), timeInNanoseconds: 0, repeatIntervalInNanoseconds: 0)
        try gesture.drag(to: ViewportCell(column: 6, row: 0), pixel: (x: 53, y: 8), cellWidth: 8, screenHeight: 48)
        #expect(terminal.selectedText() == "two")
        try gesture.release(at: ViewportCell(column: 6, row: 0))
        let state = try RenderState()
        try state.update(from: terminal)
        var selected: [ClosedRange<UInt16>?] = []
        try state.forEachRow(onlyChanged: false) { selected.append($0.selectedColumns) }
        #expect(selected == [4...6, nil, nil])
    }

    @Test func aDragAtTheEdgeAsksForAutoscrollAndATickScrollsAndGrowsTheSelection() throws {
        let terminal = try makeTerminal(columns: 20, rows: 3)
        terminal.write((1...10).map { "line \($0)\r\n" }.joined())
        let gesture = try SelectionGesture(for: terminal)
        try gesture.press(at: ViewportCell(column: 2, row: 1), pixel: (x: 20, y: 24), timeInNanoseconds: 0, repeatIntervalInNanoseconds: 0)
        try gesture.drag(to: ViewportCell(column: 2, row: 1), pixel: (x: 20, y: 24), cellWidth: 8, screenHeight: 48)
        #expect(gesture.autoscroll == .none)
        try gesture.drag(to: ViewportCell(column: 5, row: 0), pixel: (x: 44, y: -6), cellWidth: 8, screenHeight: 48)
        #expect(gesture.autoscroll == .up)
        let before = terminal.scrollbar.firstVisibleRow
        try gesture.autoscrollTick(at: ViewportCell(column: 5, row: 0), pixel: (x: 44, y: -6), cellWidth: 8, screenHeight: 48)
        #expect(terminal.scrollbar.firstVisibleRow == before - 1)
        #expect(terminal.selectedText()?.contains("line") == true)
        try gesture.drag(to: ViewportCell(column: 5, row: 2), pixel: (x: 44, y: 60), cellWidth: 8, screenHeight: 48)
        #expect(gesture.autoscroll == .down)
        try gesture.release(at: ViewportCell(column: 5, row: 2))
        #expect(gesture.autoscroll == .none)
    }
}
