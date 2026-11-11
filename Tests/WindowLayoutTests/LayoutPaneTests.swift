import Foundation
import Testing
@testable import WindowLayout

@Suite struct LayoutPaneTests {
    let a = UUID(), b = UUID(), c = UUID()

    private func tree() -> LayoutPane {
        .split(LayoutSplit(direction: .sideBySide, fraction: 0.6, first: .session(a),
                           second: .split(LayoutSplit(direction: .stacked, first: .session(b), second: .session(c)))))
    }

    @Test func theSessionsComeInReadingOrder() {
        #expect(LayoutPane.session(a).sessions == [a])
        #expect(tree().sessions == [a, b, c])
    }

    @Test func theOtherHalfTakesThePlaceOfAHalfThatGoesAway() {
        #expect(tree().keeping { $0 != b } == .split(LayoutSplit(direction: .sideBySide, fraction: 0.6, first: .session(a), second: .session(c))))
        #expect(tree().keeping { $0 == c } == .session(c))
        #expect(tree().keeping { $0 != a }?.sessions == [b, c])
        #expect(tree().keeping { _ in false } == nil)
        #expect(tree().keeping { _ in true } == tree())
    }

    @Test func aPaneKeepsItsShapeInJSON() throws {
        let data = try JSONEncoder().encode(tree())
        #expect(try JSONDecoder().decode(LayoutPane.self, from: data) == tree())
        let one = try JSONDecoder().decode(LayoutPane.self, from: Data(#"{"session":"\#(a.uuidString)"}"#.utf8))
        #expect(one == .session(a))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LayoutPane.self, from: Data(#"{"browser":{}}"#.utf8)) }
    }

    @Test func theFractionOfASplitStaysBetweenZeroAndOne() {
        #expect(LayoutSplit(direction: .stacked, fraction: 7, first: .session(a), second: .session(b)).fraction == 1)
        #expect(LayoutSplit(direction: .stacked, fraction: -1, first: .session(a), second: .session(b)).fraction == 0)
    }
}
