import CoreGraphics
import TerminalEmulation

/// Decides what a scroll of the wheel or the trackpad does.
@MainActor
final class ScrollInput {
    enum Action: Equatable {
        /// Moves the viewport through the scrollback. A negative number goes up.
        case viewport(rows: Int)
        /// Reports wheel turns to a program that asked for mouse reports.
        case wheelReports(button: MouseEvent.Button, count: Int)
        /// Sends arrow keys to a full-screen program that has no scrollback.
        case arrowKeys(up: Bool, count: Int)
    }

    private var accumulator = ScrollAccumulator()

    /// - Parameters:
    ///   - delta: The `scrollingDeltaY` of the event. A positive number goes up.
    ///   - cellHeight: The height of a row in points.
    /// - Returns: `nil` when the scroll moves no row, or when the program wants no scroll.
    func action(delta: CGFloat, isPrecise: Bool, startsGesture: Bool, cellHeight: CGFloat, terminal: Terminal) -> Action? {
        let step = accumulator.add(delta: delta, isPrecise: isPrecise, startsGesture: startsGesture, cellHeight: cellHeight)
        guard step.rows != 0 else { return nil }
        let isUp = step.rows > 0
        if terminal.isMouseTrackingActive {
            // A program that reads the mouse scrolls by itself, so it gets one report for each turn.
            return .wheelReports(button: isUp ? .wheelUp : .wheelDown, count: abs(step.ticks))
        }
        if terminal.isAlternateScreenActive {
            // Mode 1007: a full-screen program such as `less` has no scrollback, and arrow keys scroll it.
            return terminal.isModeEnabled(.alternateScroll) ? .arrowKeys(up: isUp, count: abs(step.rows)) : nil
        }
        return .viewport(rows: -step.rows)
    }
}
