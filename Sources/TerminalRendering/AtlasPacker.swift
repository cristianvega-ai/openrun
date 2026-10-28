/// Finds room for rectangles in a square texture. It fills one row of the
/// texture from left to right, then starts the next row below it.
struct AtlasPacker {
    private(set) var side: Int
    private var horizontalPosition = 0
    private var verticalPosition = 0
    private var rowHeight = 0

    init(side: Int) {
        self.side = side
    }

    /// The top left corner of a free area, or `nil` when the texture is full.
    /// A gap of one pixel keeps each bitmap apart from its neighbors.
    mutating func place(width: Int, height: Int) -> (horizontalPosition: Int, verticalPosition: Int)? {
        if horizontalPosition + width > side {
            horizontalPosition = 0
            verticalPosition += rowHeight
            rowHeight = 0
        }
        guard width <= side, verticalPosition + height <= side else { return nil }
        defer {
            horizontalPosition += width + 1
            rowHeight = max(rowHeight, height + 1)
        }
        return (horizontalPosition, verticalPosition)
    }

    /// Forgets every place, so a full texture can take new bitmaps.
    mutating func reset() {
        self = AtlasPacker(side: side)
    }

    /// Keeps all places when the texture grows.
    mutating func grow(to side: Int) {
        self.side = side
    }
}
