import CoreGraphics

/// The Powerline symbols U+E0B0 to U+E0BF in the private use area: the
/// arrows, half circles and slopes that separate the parts of a prompt or a
/// status line. A solid symbol fills the cell from top to bottom, so it meets
/// the colored backgrounds of its neighbors with no gap.
enum PowerlineSymbols {
    /// Draws the character, or returns `false` for one outside the set.
    static func draw(_ scalar: Unicode.Scalar, on canvas: inout CellCanvas) -> Bool {
        guard (0xE0B0...0xE0BF).contains(scalar.value) else { return false }
        let (width, height) = (CGFloat(canvas.width), CGFloat(canvas.height))
        let light = CGFloat(canvas.lightThickness)
        let (topLeft, topRight) = (CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0))
        let (bottomLeft, bottomRight) = (CGPoint(x: 0, y: height), CGPoint(x: width, y: height))
        let (middleLeft, middleRight) = (CGPoint(x: 0, y: height / 2), CGPoint(x: width, y: height / 2))
        // Each symbol is a path, and every second one is its outline or line in place of a fill.
        let points: [CGPoint]
        var isCurve = false
        switch scalar.value {
        case 0xE0B0, 0xE0B1: points = [topLeft, middleRight, bottomLeft]
        case 0xE0B2, 0xE0B3: points = [topRight, middleLeft, bottomRight]
        case 0xE0B4, 0xE0B5: (points, isCurve) = ([topLeft, middleRight, bottomLeft], true)
        case 0xE0B6, 0xE0B7: (points, isCurve) = ([topRight, middleLeft, bottomRight], true)
        case 0xE0B8: points = [topLeft, bottomRight, bottomLeft]
        case 0xE0BA: points = [topRight, bottomRight, bottomLeft]
        case 0xE0BC: points = [topLeft, topRight, bottomLeft]
        case 0xE0BE: points = [topLeft, topRight, bottomRight]
        case 0xE0B9, 0xE0BF: points = [topLeft, bottomRight]
        default: points = [topRight, bottomLeft]
        }
        let isOutline = scalar.value % 2 == 1
        canvas.draw { context in
            if isCurve {
                // Half of an ellipse with its flat side on one edge of the cell.
                let isRight = points[0] == topLeft
                let inset = isOutline ? light / 2 : 0
                let box = CGRect(x: isRight ? -width : 0, y: inset, width: 2 * width, height: height - 2 * inset)
                context.addEllipse(in: box.insetBy(dx: inset, dy: 0))
            } else {
                context.addLines(between: points)
                if !isOutline { context.closePath() }
            }
            if isOutline {
                context.setLineWidth(light)
                context.strokePath()
            } else {
                context.fillPath()
            }
        }
        return true
    }
}
