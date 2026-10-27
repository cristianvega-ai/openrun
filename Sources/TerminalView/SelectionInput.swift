import AppKit
import TerminalEmulation

/// Selects text with the pointer: a drag selects cells, a double click a word
/// and a triple click a line. libghostty-vt has the rules. The view only gives it the
/// pointer and the time.
///
/// The calls use `try?`. The only error is a cell that is not in the viewport,
/// and then the pointer selects nothing.
@MainActor
final class SelectionInput {
    private let terminal: Terminal
    private let gesture: SelectionGesture

    init(terminal: Terminal) throws {
        self.terminal = terminal
        gesture = try SelectionGesture(for: terminal)
    }

    /// A press of the left button. libghostty-vt selects only for a double or triple click, so a
    /// single press clears the old selection here.
    func press(at point: CGPoint, in location: PointerLocation, timestamp: TimeInterval) {
        terminal.clearSelection()
        try? gesture.press(
            at: location.cell(of: point), pixel: location.unclampedPixel(of: point), timeInNanoseconds: UInt64(timestamp * 1e9),
            repeatIntervalInNanoseconds: UInt64(NSEvent.doubleClickInterval * 1e9))
    }

    func drag(to point: CGPoint, in location: PointerLocation) {
        let width = UInt32((location.cellSize.width * location.scale).rounded())
        let height = UInt32((CGFloat(location.gridSize.rows) * location.cellSize.height * location.scale).rounded())
        try? gesture.drag(to: location.cell(of: point), pixel: location.unclampedPixel(of: point), cellWidth: width, screenHeight: height)
    }

    func release(at point: CGPoint, in location: PointerLocation) {
        try? gesture.release(at: location.cell(of: point))
    }
}
