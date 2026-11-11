import CoreGraphics

/// The size of the text of a view in points. The user makes it larger or
/// smaller by one point, and goes back to the standard size: 13 points, or
/// the size that the owner of the view chose.
struct FontSizeControl: Equatable {
    static let standard: CGFloat = 13
    /// Limits that only stop a size nobody can read, and a grid that is too large.
    static let range: ClosedRange<CGFloat> = 6...72
    private(set) var pointSize = standard
    private(set) var standardSize = standard

    /// Each call gives `true` when the size changed.
    mutating func larger() -> Bool { set(pointSize + 1) }
    mutating func smaller() -> Bool { set(pointSize - 1) }
    mutating func reset() -> Bool { set(standardSize) }

    /// A new standard size, inside the limits. The text takes it at once.
    mutating func setStandard(_ size: CGFloat) -> Bool {
        standardSize = min(max(size, Self.range.lowerBound), Self.range.upperBound)
        return set(standardSize)
    }

    private mutating func set(_ size: CGFloat) -> Bool {
        let new = min(max(size, Self.range.lowerBound), Self.range.upperBound)
        defer { pointSize = new }
        return new != pointSize
    }
}
