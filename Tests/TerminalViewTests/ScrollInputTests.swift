import CoreGraphics
import Testing
@testable import TerminalView

@Suite struct ScrollAccumulatorTests {
    @Test func aTurnOfAWheelMovesThreeRowsAndASlowTurnMovesOneTurn() {
        var accumulator = ScrollAccumulator()
        func add(_ delta: CGFloat) -> ScrollAccumulator.Step {
            accumulator.add(delta: delta, isPrecise: false, startsGesture: false, cellHeight: 15.5)
        }
        #expect(add(1) == .init(rows: 3, ticks: 1))
        #expect(add(-1) == .init(rows: -3, ticks: -1))
        #expect(add(0.2) == .init(rows: 3, ticks: 1))
        #expect(add(-0.2) == .init(rows: -3, ticks: -1))
        #expect(add(5) == .init(rows: 15, ticks: 5))
        #expect(add(0) == .init(rows: 0, ticks: 0))
    }

    @Test func aTrackpadAddsPointsUntilTheyMakeARowAndKeepsTheRest() {
        var accumulator = ScrollAccumulator()
        func add(_ delta: CGFloat, starts: Bool = false) -> Int {
            accumulator.add(delta: delta, isPrecise: true, startsGesture: starts, cellHeight: 10).rows
        }
        #expect([add(4), add(4), add(4), add(4), add(4)] == [0, 0, 1, 0, 1])
        #expect(add(-25) == -2)
        #expect([add(-4), add(-1)] == [0, -1])
    }

    @Test func aNewGestureForgetsTheRestOfTheLastOne() {
        var accumulator = ScrollAccumulator()
        _ = accumulator.add(delta: 9, isPrecise: true, startsGesture: false, cellHeight: 10)
        #expect(accumulator.add(delta: 2, isPrecise: true, startsGesture: false, cellHeight: 10).rows == 1)
        _ = accumulator.add(delta: 9, isPrecise: true, startsGesture: false, cellHeight: 10)
        #expect(accumulator.add(delta: 2, isPrecise: true, startsGesture: true, cellHeight: 10).rows == 0)
    }
}
