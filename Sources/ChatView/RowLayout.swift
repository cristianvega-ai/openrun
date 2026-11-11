import CoreGraphics

/// The heights and the places of the rows of the transcript view.
///
/// A row that the view has not measured has an estimated height. The tops
/// of the rows are a running sum that is computed again only from the
/// first row that changed, so a change at the end costs little however
/// many rows there are.
struct RowLayout {
    private(set) var keys: [String] = []
    private(set) var heights: [CGFloat] = []
    private(set) var isMeasured: [Bool] = []
    private var indexes: [String: Int] = [:]
    /// The top of each row, and the total height at the end.
    private var tops: [CGFloat] = [0]
    /// The entries of `tops` up to this index are right.
    private var validTops = 0

    var count: Int { keys.count }

    /// Takes the rows in their new order. A row that stays keeps its
    /// height, and a changed row keeps its old height as an estimate.
    mutating func update(keys newKeys: [String], changed: Set<String>, estimate: (Int) -> CGFloat) {
        var newHeights: [CGFloat] = []
        var newMeasured: [Bool] = []
        newHeights.reserveCapacity(newKeys.count)
        newMeasured.reserveCapacity(newKeys.count)
        var firstDifference = min(keys.count, newKeys.count)
        for (index, key) in newKeys.enumerated() {
            if let old = index < keys.count && keys[index] == key ? index : indexes[key] {
                newHeights.append(heights[old])
                newMeasured.append(isMeasured[old] && !changed.contains(key))
                if old != index || changed.contains(key) { firstDifference = min(firstDifference, index) }
            } else {
                newHeights.append(estimate(index))
                newMeasured.append(false)
                firstDifference = min(firstDifference, index)
            }
        }
        if newKeys.count != keys.count || firstDifference < newKeys.count { indexes = [:] }
        keys = newKeys
        heights = newHeights
        isMeasured = newMeasured
        if indexes.isEmpty { for (index, key) in keys.enumerated() { indexes[key] = index } }
        tops = Array(tops.prefix(firstDifference + 1)) + Array(repeating: 0, count: keys.count - firstDifference)
        validTops = min(validTops, firstDifference)
    }

    func index(of key: String) -> Int? {
        indexes[key]
    }

    mutating func setMeasuredHeight(_ height: CGFloat, at index: Int) {
        isMeasured[index] = true
        guard heights[index] != height else { return }
        heights[index] = height
        validTops = min(validTops, index)
    }

    /// Marks every height as an estimate, as after a change of the width.
    mutating func forgetMeasurements() {
        isMeasured = Array(repeating: false, count: keys.count)
    }

    mutating func top(of index: Int) -> CGFloat {
        if validTops < index {
            for row in validTops..<index { tops[row + 1] = tops[row] + heights[row] }
            validTops = index
        }
        return tops[index]
    }

    mutating func totalHeight() -> CGFloat {
        top(of: keys.count)
    }

    /// The row that holds the point `y`, or the nearest row.
    mutating func index(at y: CGFloat) -> Int {
        guard !keys.isEmpty else { return 0 }
        _ = totalHeight()
        var low = 0
        var high = keys.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if tops[middle] <= y { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
