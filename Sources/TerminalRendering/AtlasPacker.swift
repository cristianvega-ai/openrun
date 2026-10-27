/// Finds room for rectangles in a square texture. It fills one row of the
/// texture from left to right, then starts the next row below it.
struct AtlasPacker {
    let side: Int
    private var x = 0
    private var y = 0
    private var rowHeight = 0

    init(side: Int) {
        self.side = side
    }

    /// The top left corner of a free area, or `nil` when the texture is full.
    /// A gap of one pixel keeps each bitmap apart from its neighbors.
    mutating func place(width: Int, height: Int) -> (x: Int, y: Int)? {
        if x + width > side {
            x = 0
            y += rowHeight
            rowHeight = 0
        }
        guard width <= side, y + height <= side else { return nil }
        defer {
            x += width + 1
            rowHeight = max(rowHeight, height + 1)
        }
        return (x, y)
    }

    /// Forgets every place, so a full texture can take new bitmaps.
    mutating func reset() {
        self = AtlasPacker(side: side)
    }
}
