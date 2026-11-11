import CoreGraphics
import Testing

@testable import ChatView

struct RowLayoutViewportTests {
    /// A hundred rows with an estimate of 100 points each.
    func layout() -> RowLayout {
        var layout = RowLayout()
        layout.update(keys: (0..<100).map { "row\($0)" }, changed: []) { _ in 100 }
        return layout
    }

    @Test func withNoAnchorTheScreenShowsTheBottom() {
        var layout = layout()
        let origin = layout.settle(keeping: nil, viewport: 300, bottomPadding: 20) { _ in 50 }
        #expect(origin == layout.totalHeight() + 20 - 300)
        #expect(layout.isMeasured[99])
        #expect(!layout.isMeasured[0])
    }

    @Test func rowsAboveTheAnchorThatGrowDoNotMoveIt() {
        var layout = layout()
        let anchor = layout.anchor(at: 5_030)
        #expect(anchor == RowLayout.Anchor(key: "row50", offset: 30))
        layout.update(keys: layout.keys, changed: ["row10"]) { _ in 100 }
        layout.setMeasuredHeight(400, at: 10)
        let origin = layout.settle(keeping: anchor, viewport: 300, bottomPadding: 0) { _ in 100 }
        #expect(origin == 5_330)
    }

    @Test func theNearRowsReachHalfAScreenPastTheScreen() {
        var layout = layout()
        #expect(layout.rows(near: 1_000, viewport: 200) == 9...13)
        #expect(layout.rows(near: 0, viewport: 200) == 0...3)
    }
}
