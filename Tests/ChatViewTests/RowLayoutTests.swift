import CoreGraphics
import Testing
@testable import ChatView

struct RowLayoutTests {
    private func layout(_ keys: [String], height: CGFloat = 10) -> RowLayout {
        var layout = RowLayout()
        layout.update(keys: keys, changed: [], estimate: { _ in height })
        return layout
    }

    @Test func topsAreARunningSumOfTheHeights() {
        var layout = layout(["a", "b", "c"])
        layout.setMeasuredHeight(25, at: 1)
        #expect([0, 1, 2, 3].map { layout.top(of: $0) } == [0, 10, 35, 45])
        #expect(layout.totalHeight() == 45)
        #expect([0, 9.9, 10, 34, 35, 100, -5].map { layout.index(at: $0) } == [0, 0, 1, 1, 2, 2, 0])
    }

    @Test func rowsThatStayKeepTheirHeights() {
        var layout = layout(["a", "b", "c"])
        layout.setMeasuredHeight(30, at: 0)
        layout.setMeasuredHeight(40, at: 2)
        layout.update(keys: ["b", "c", "d"], changed: [], estimate: { _ in 5 })
        #expect(layout.heights == [10, 40, 5])
        #expect(layout.isMeasured == [false, true, false])
        #expect(layout.index(of: "c") == 1)
        #expect(layout.index(of: "a") == nil)
        #expect(layout.totalHeight() == 55)
    }

    @Test func aChangedRowKeepsItsHeightAsAnEstimate() {
        var layout = layout(["a", "b"])
        layout.setMeasuredHeight(30, at: 1)
        _ = layout.totalHeight()
        layout.update(keys: ["a", "b"], changed: ["b"], estimate: { _ in 1 })
        #expect(layout.heights == [10, 30])
        #expect(layout.isMeasured == [false, false])
        layout.setMeasuredHeight(50, at: 1)
        #expect(layout.totalHeight() == 60)
    }

    @Test func forgottenMeasurementsStayAsEstimates() {
        var layout = layout(["a"])
        layout.setMeasuredHeight(30, at: 0)
        layout.forgetMeasurements()
        #expect(layout.isMeasured == [false])
        #expect(layout.totalHeight() == 30)
    }

    @Test func tenThousandRowsUpdateAtTheEndQuickly() {
        let keys = (0..<10_000).map { "row \($0)" }
        var layout = layout(keys)
        _ = layout.totalHeight()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<60 {
                layout.update(keys: keys, changed: ["row 9999"], estimate: { _ in 10 })
                layout.setMeasuredHeight(20, at: 9_999)
                _ = layout.totalHeight()
            }
        }
        #expect(elapsed / 60 < .milliseconds(10))
    }
}
