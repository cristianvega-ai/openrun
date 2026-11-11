import TerminalEmulation

/// Quadrilaterals that cover the whole picture, over the text and the cursor.
enum OverlayQuadrilaterals {
    /// The flash of the visual bell: one rectangle of the text color. It is translucent, so the
    /// text under it stays readable.
    static func flash(width: Int, height: Int, color: TerminalColor) -> CellQuadrilateral {
        var quadrilateral = CellQuadrilateral.rectangle(horizontalPosition: 0, verticalPosition: 0, width: width, height: height, color: color)
        quadrilateral.color.w = 0.3
        return quadrilateral
    }

    /// The underline of a link under the pointer, in the text color, at the place
    /// of a single underline. It goes over the text, as the lines of the cells do.
    static func underlines(of runs: [ViewportCellRun], color: TerminalColor, metrics: CellMetrics, padding: Int) -> [CellQuadrilateral] {
        runs.filter { !$0.columns.isEmpty }.map { run in
            .rectangle(horizontalPosition: padding + run.columns.lowerBound * metrics.width,
                       verticalPosition: padding + run.row * metrics.height + metrics.underlinePosition,
                       width: run.columns.count * metrics.width, height: metrics.underlineThickness, color: color)
        }
    }
}
