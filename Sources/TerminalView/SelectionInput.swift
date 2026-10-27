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
    /// The last drag. A step of the autoscroll uses it, because the pointer can rest.
    private var lastDrag: (point: CGPoint, location: PointerLocation)?

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

    var autoscroll: SelectionAutoscroll { gesture.autoscroll }

    func drag(to point: CGPoint, in location: PointerLocation) {
        lastDrag = (point, location)
        let (width, height) = geometry(of: location)
        try? gesture.drag(to: location.cell(of: point), pixel: location.unclampedPixel(of: point), cellWidth: width, screenHeight: height)
    }

    /// Scrolls one row in the direction of the autoscroll and grows the selection to the pointer.
    func autoscrollTick() {
        guard let (point, location) = lastDrag else { return }
        let (width, height) = geometry(of: location)
        try? gesture.autoscrollTick(at: location.cell(of: point), pixel: location.unclampedPixel(of: point), cellWidth: width, screenHeight: height)
    }

    func release(at point: CGPoint, in location: PointerLocation) {
        lastDrag = nil
        try? gesture.release(at: location.cell(of: point))
    }

    private func geometry(of location: PointerLocation) -> (UInt32, UInt32) {
        (UInt32((location.cellSize.width * location.scale).rounded()),
         UInt32((CGFloat(location.gridSize.rows) * location.cellSize.height * location.scale).rounded()))
    }
}
