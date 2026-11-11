import CoreGraphics

/// The place of the screen over the rows.
extension RowLayout {
    /// A row and the distance of the top of the screen below its top.
    struct Anchor: Equatable {
        var key: String
        var offset: CGFloat
    }

    /// The row at the top of a screen at `origin`.
    mutating func anchor(at origin: CGFloat) -> Anchor? {
        guard count > 0 else { return nil }
        let index = index(at: origin)
        return Anchor(key: keys[index], offset: origin - top(of: index))
    }

    /// The origin of the screen that keeps the anchor at its place, or that
    /// shows the bottom when there is no anchor or the anchor went.
    mutating func origin(keeping anchor: Anchor?, viewport: CGFloat, bottomPadding: CGFloat) -> CGFloat {
        let maximum = max(0, totalHeight() + bottomPadding - viewport)
        guard let anchor, let index = index(of: anchor.key) else { return maximum }
        return min(maximum, max(0, top(of: index) + anchor.offset))
    }

    /// The rows from half a screen above to half a screen below a screen
    /// at `origin`. They have views, so a short scroll shows no gap.
    mutating func rows(near origin: CGFloat, viewport: CGFloat) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        return index(at: origin - viewport / 2)...index(at: origin + viewport * 1.5)
    }

    /// Measures the rows near the screen and returns the origin of the
    /// screen that keeps the anchor at its place.
    /// - Parameter measure: The true height of the row at an index.
    mutating func settle(
        keeping anchor: Anchor?, viewport: CGFloat, bottomPadding: CGFloat, measure: (Int) -> CGFloat
    ) -> CGFloat {
        // A measured height moves the rows below it and can bring other
        // rows near the screen, so a few passes find a still place.
        for _ in 0..<4 {
            let origin = origin(keeping: anchor, viewport: viewport, bottomPadding: bottomPadding)
            guard let range = rows(near: origin, viewport: viewport) else { break }
            var isChanged = false
            for index in range where !isMeasured[index] {
                let height = measure(index)
                isChanged = isChanged || height != heights[index]
                setMeasuredHeight(height, at: index)
            }
            if !isChanged { break }
        }
        return origin(keeping: anchor, viewport: viewport, bottomPadding: bottomPadding)
    }
}
