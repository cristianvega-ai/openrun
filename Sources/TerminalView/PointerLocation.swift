import CoreGraphics
import TerminalEmulation

/// Turns a point of the view into a position in the grid. AppKit counts
/// points from the bottom left of the view, and the grid counts from its
/// top left, inside the padding.
struct PointerLocation {
    /// The size of a cell in points.
    let cellSize: CGSize
    /// The space around the grid in points.
    let padding: CGFloat
    /// The number of pixels for each point.
    let scale: CGFloat
    let gridSize: TerminalSize
    let viewHeight: CGFloat

    /// The point in pixels from the top left of the grid, as `MouseEvent` wants it.
    /// A drag can leave the view, so the pixel stays inside the grid.
    func pixel(of point: CGPoint) -> (x: Float, y: Float) {
        let width = CGFloat(gridSize.columns) * cellSize.width * scale, height = CGFloat(gridSize.rows) * cellSize.height * scale
        let x = (point.x - padding) * scale, y = (viewHeight - point.y - padding) * scale
        return (Float(min(max(x, 0), width - 1)), Float(min(max(y, 0), height - 1)))
    }

    /// The cell under the point, or the cell of the edge that is nearest to it.
    func cell(of point: CGPoint) -> ViewportCell {
        let pixel = pixel(of: point)
        return ViewportCell(
            column: UInt16(CGFloat(pixel.x) / (cellSize.width * scale)), row: UInt32(CGFloat(pixel.y) / (cellSize.height * scale)))
    }
}
