import CoreGraphics

/// Adds up the movement of the wheel and the trackpad into whole rows.
struct ScrollAccumulator {
    /// How far a scroll went. A positive number goes up, toward the older rows, as
    /// `scrollingDeltaY` of AppKit does.
    struct Step: Equatable {
        /// The rows to scroll.
        var rows: Int
        /// The turns of a wheel. A trackpad has no turns, and its turns are its rows.
        var ticks: Int
    }

    /// The rows that one turn of a wheel moves.
    static let rowsForEachTick = 3
    /// The movement of a trackpad that did not make a row yet, in points.
    private var rest: CGFloat = 0

    /// - Parameters:
    ///   - delta: The `scrollingDeltaY` of the event.
    ///   - isPrecise: The event comes from a trackpad, and its delta is in points. A wheel gives
    ///     its delta in turns.
    ///   - startsGesture: The fingers just touched the trackpad. The rest of the last gesture is gone.
    ///   - cellHeight: The height of a row in points.
    mutating func add(delta: CGFloat, isPrecise: Bool, startsGesture: Bool, cellHeight: CGFloat) -> Step {
        if startsGesture { rest = 0 }
        guard isPrecise else {
            // A slow turn can have a delta below one. It still moves the rows of one turn.
            let ticks = delta == 0 ? 0 : max(1, Int(abs(delta).rounded())) * (delta < 0 ? -1 : 1)
            return Step(rows: ticks * Self.rowsForEachTick, ticks: ticks)
        }
        rest += delta
        let rows = Int(rest / cellHeight)
        rest -= CGFloat(rows) * cellHeight
        return Step(rows: rows, ticks: rows)
    }
}
