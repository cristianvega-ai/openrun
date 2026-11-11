import CoreGraphics

/// The box drawing characters that are not straight arms: the dashed lines,
/// the rounded corners and the diagonals. Agents draw their frames with the
/// rounded corners, so each corner meets a light line of its neighbor exactly.
enum BoxDrawingShapes {
    /// Draws the character, or returns `false` for one that is not such a shape.
    static func draw(_ scalar: Unicode.Scalar, on canvas: inout CellCanvas) -> Bool {
        let light = canvas.lightThickness
        switch scalar.value {
        case 0x2504...0x250B:
            // Triple dashes, then quadruple dashes: light and heavy, horizontal and vertical.
            let index = Int(scalar.value - 0x2504)
            dashes(count: index < 4 ? 3 : 4, thickness: index % 2 == 0 ? light : 2 * light, isVertical: index % 4 >= 2, on: &canvas)
        case 0x254C...0x254F:
            let index = Int(scalar.value - 0x254C)
            dashes(count: 2, thickness: index % 2 == 0 ? light : 2 * light, isVertical: index >= 2, on: &canvas)
        case 0x256D...0x2570:
            corner(scalar.value, on: &canvas)
        case 0x2571...0x2573:
            diagonals(rising: scalar.value != 0x2572, falling: scalar.value != 0x2571, on: &canvas)
        default:
            return false
        }
        return true
    }

    /// Each cell has the same pattern, and half of a gap at each end, so the
    /// dashes of a row of cells have even gaps also between the cells.
    private static func dashes(count: Int, thickness: Int, isVertical: Bool, on canvas: inout CellCanvas) {
        let length = isVertical ? canvas.height : canvas.width
        let across = ((isVertical ? canvas.width : canvas.height) - thickness) / 2
        // A small cell has room for fewer dashes, because each one needs a pixel and a gap.
        let count = min(count, max(1, length / 2))
        let segment = Double(length) / Double(count)
        let gap = max(1, Int((segment * 0.35).rounded()))
        for index in 0..<count {
            let start = index * length / count + gap / 2, end = (index + 1) * length / count - (gap - gap / 2)
            if isVertical {
                canvas.fill(left: across, top: start, right: across + thickness, bottom: end)
            } else {
                canvas.fill(left: start, top: across, right: end, bottom: across + thickness)
            }
        }
    }

    /// A quarter circle between the middle of two edges. The stroke has the
    /// thickness and the place of a light line, so its ends are sharp where
    /// they meet the lines of the neighbors.
    private static func corner(_ value: UInt32, on canvas: inout CellCanvas) {
        let light = canvas.lightThickness
        let (width, height) = (CGFloat(canvas.width), CGFloat(canvas.height))
        let middle = CGPoint(
            x: CGFloat((canvas.width - light) / 2) + CGFloat(light) / 2, y: CGFloat((canvas.height - light) / 2) + CGFloat(light) / 2)
        // U+256D goes down and right, U+256E down and left, U+256F up and left, U+2570 up and right.
        let isDown = value <= 0x256E, isRight = value == 0x256D || value == 0x2570
        let vertical = CGPoint(x: middle.x, y: isDown ? height : 0)
        let horizontal = CGPoint(x: isRight ? width : 0, y: middle.y)
        // The arc ends a pixel before the edges, so the last column and row are straight and sharp.
        let radius = max(0.5, min(isRight ? width - middle.x : middle.x, isDown ? height - middle.y : middle.y) - 1)
        canvas.draw { context in
            context.setLineWidth(CGFloat(light))
            context.move(to: vertical)
            context.addArc(tangent1End: middle, tangent2End: horizontal, radius: radius)
            context.addLine(to: horizontal)
            context.strokePath()
        }
    }

    /// Lines from corner to corner. They go on past the corners, so the cut at
    /// the edge of the cell meets the line of the next cell on the diagonal.
    private static func diagonals(rising: Bool, falling: Bool, on canvas: inout CellCanvas) {
        let (width, height) = (CGFloat(canvas.width), CGFloat(canvas.height))
        let light = CGFloat(canvas.lightThickness)
        canvas.draw { context in
            context.setLineWidth(light)
            if rising {
                context.move(to: CGPoint(x: -width, y: 2 * height))
                context.addLine(to: CGPoint(x: 2 * width, y: -height))
            }
            if falling {
                context.move(to: CGPoint(x: -width, y: -height))
                context.addLine(to: CGPoint(x: 2 * width, y: 2 * height))
            }
            context.strokePath()
        }
    }
}
