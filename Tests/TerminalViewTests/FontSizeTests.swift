import Testing
@testable import TerminalView

@Suite struct FontSizeControlTests {
    @Test func theSizeStartsAt13PointsAndMovesByOnePoint() {
        var control = FontSizeControl()
        #expect(control.pointSize == 13)
        let larger = control.larger()
        #expect(larger && control.pointSize == 14)
        let smaller = control.smaller()
        #expect(smaller && control.pointSize == 13)
    }

    @Test func resetGoesBackTo13PointsAndTellsWhenNothingChanged() {
        var control = FontSizeControl()
        _ = control.larger()
        _ = control.larger()
        let reset = control.reset()
        let again = control.reset()
        #expect(reset && control.pointSize == 13)
        #expect(!again)
    }

    @Test func theSizeStopsAtTheLimits() {
        var control = FontSizeControl()
        for _ in 0..<100 { _ = control.larger() }
        let atLargest = control.larger()
        #expect(control.pointSize == 72 && !atLargest)
        for _ in 0..<100 { _ = control.smaller() }
        #expect(control.pointSize == 6)
    }
}
