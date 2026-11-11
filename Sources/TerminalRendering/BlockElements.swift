/// The Block Elements, U+2580 to U+259F: parts of the cell in eighths, the
/// quadrants and the shades. Programs draw bars and pictures with them, so
/// every part ends on the same pixel as the part that completes it.
enum BlockElements {
    /// Draws the character, or returns `false` for one outside the block.
    static func draw(_ scalar: Unicode.Scalar, on canvas: inout CellCanvas) -> Bool {
        let (width, height) = (canvas.width, canvas.height)
        // The place of n eighths, from the left or the top. The lower half of the
        // cell starts where the upper half ends, so no row is drawn twice or missed.
        func across(_ eighths: Int) -> Int { Int((Double(width) * Double(eighths) / 8).rounded()) }
        func down(_ eighths: Int) -> Int { Int((Double(height) * Double(eighths) / 8).rounded()) }
        switch scalar.value {
        case 0x2580:
            canvas.fill(left: 0, top: 0, right: width, bottom: down(4))
        case 0x2581...0x2588:
            // Lower one eighth to the full block.
            canvas.fill(left: 0, top: down(8 - Int(scalar.value - 0x2580)), right: width, bottom: height)
        case 0x2589...0x258F:
            // Left seven eighths to left one eighth.
            canvas.fill(left: 0, top: 0, right: across(8 - Int(scalar.value - 0x2588)), bottom: height)
        case 0x2590:
            canvas.fill(left: across(4), top: 0, right: width, bottom: height)
        case 0x2591...0x2593:
            // A shade is an even part of the color, so the shades of two cells look the same where they meet.
            canvas.fill(left: 0, top: 0, right: width, bottom: height, coverage: [64, 128, 191][Int(scalar.value - 0x2591)])
        case 0x2594:
            canvas.fill(left: 0, top: 0, right: width, bottom: down(1))
        case 0x2595:
            canvas.fill(left: across(7), top: 0, right: width, bottom: height)
        case 0x2596...0x259F:
            // The quadrants as bits: upper left 1, upper right 2, lower left 4, lower right 8.
            let quadrants: [Int] = [4, 8, 1, 1 | 4 | 8, 1 | 8, 1 | 2 | 4, 1 | 2 | 8, 2, 2 | 4, 2 | 4 | 8]
            let bits = quadrants[Int(scalar.value - 0x2596)]
            let (middle, center) = (across(4), down(4))
            if bits & 1 != 0 { canvas.fill(left: 0, top: 0, right: middle, bottom: center) }
            if bits & 2 != 0 { canvas.fill(left: middle, top: 0, right: width, bottom: center) }
            if bits & 4 != 0 { canvas.fill(left: 0, top: center, right: middle, bottom: height) }
            if bits & 8 != 0 { canvas.fill(left: middle, top: center, right: width, bottom: height) }
        default:
            return false
        }
        return true
    }
}
