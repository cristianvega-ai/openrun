import CoreGraphics

/// The size of the text of a view in points. The user makes it larger or
/// smaller by one point, and goes back to the standard size of 13 points.
struct FontSizeControl: Equatable {
    static let standard: CGFloat = 13
    /// Limits that only stop a size nobody can read, and a grid that is too large.
    static let range: ClosedRange<CGFloat> = 6...72
    private(set) var pointSize = standard

    /// Each call gives `true` when the size changed.
    mutating func larger() -> Bool { set(pointSize + 1) }
    mutating func smaller() -> Bool { set(pointSize - 1) }
    mutating func reset() -> Bool { set(Self.standard) }

    private mutating func set(_ size: CGFloat) -> Bool {
        let new = min(max(size, Self.range.lowerBound), Self.range.upperBound)
        defer { pointSize = new }
        return new != pointSize
    }
}
