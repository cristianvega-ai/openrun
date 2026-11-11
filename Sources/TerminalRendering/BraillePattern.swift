import CoreGraphics

/// The Braille Patterns, U+2800 to U+28FF: two columns of four dots. Programs
/// draw graphs with them, so the dots keep the same distance also from one
/// cell to the next, and the 256 patterns line up.
enum BraillePattern {
    /// Draws the character, or returns `false` for one outside the block.
    static func draw(_ scalar: Unicode.Scalar, on canvas: inout CellCanvas) -> Bool {
        guard (0x2800...0x28FF).contains(scalar.value) else { return false }
        let bits = Int(scalar.value - 0x2800)
        let (width, height) = (Double(canvas.width), Double(canvas.height))
        let side = max(1, Int((width / 4).rounded()))
        // The middle of each dot is at the middle of its quarter of the width
        // and its eighth of the height, so the space between cells is the space between dots.
        func left(_ column: Int) -> Int { Int((width * Double(2 * column + 1) / 4 - Double(side) / 2).rounded()) }
        func top(_ row: Int) -> Int { Int((height * Double(2 * row + 1) / 8 - Double(side) / 2).rounded()) }
        // The bit of each dot: dots 1, 2, 3 and 7 on the left, then 4, 5, 6 and 8 on the right.
        let dots = [(0, 0, 0), (0, 1, 1), (0, 2, 2), (1, 0, 3), (1, 1, 4), (1, 2, 5), (0, 3, 6), (1, 3, 7)]
        let shown = dots.filter { bits & (1 << $0.2) != 0 }
        // A small dot stays a sharp square. A larger one is round, as in a font.
        guard side >= 4 else {
            for (column, row, _) in shown { canvas.fill(left: left(column), top: top(row), right: left(column) + side, bottom: top(row) + side) }
            return true
        }
        canvas.draw { context in
            for (column, row, _) in shown {
                context.fillEllipse(in: CGRect(x: left(column), y: top(row), width: side, height: side))
            }
        }
        return true
    }
}
