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

    /// The point in pixels from the top left of the grid. It can be outside the grid, because a
    /// drag of the selection that leaves the grid asks the viewport to scroll.
    func unclampedPixel(of point: CGPoint) -> (horizontalPosition: Double, verticalPosition: Double) {
        (Double((point.x - padding) * scale), Double((viewHeight - point.y - padding) * scale))
    }

    /// The point in pixels from the top left of the grid, as `MouseEvent` wants it.
    /// A drag can leave the view, so the pixel stays inside the grid.
    func pixel(of point: CGPoint) -> (horizontalPosition: Float, verticalPosition: Float) {
        let width = CGFloat(gridSize.columns) * cellSize.width * scale, height = CGFloat(gridSize.rows) * cellSize.height * scale
        let raw = unclampedPixel(of: point)
        return (Float(min(max(raw.horizontalPosition, 0), width - 1)), Float(min(max(raw.verticalPosition, 0), height - 1)))
    }

    /// The cell under the point, or the cell of the edge that is nearest to it.
    func cell(of point: CGPoint) -> ViewportCell {
        let pixel = pixel(of: point)
        return ViewportCell(
            column: UInt16(CGFloat(pixel.horizontalPosition) / (cellSize.width * scale)), row: UInt32(CGFloat(pixel.verticalPosition) / (cellSize.height * scale)))
    }
}
