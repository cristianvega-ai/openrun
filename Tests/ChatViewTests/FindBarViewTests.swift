import AppKit
import Testing

@testable import ChatView

@MainActor struct FindBarViewTests {
    @Test func theBarCountsMatchesAndMoves() {
        let bar = FindBarView()
        var moves: [Int] = []
        bar.moveAction = { moves.append($0) }
        bar.field.stringValue = "row"
        bar.show(matchIndex: 1, count: 4, palette: ChatPalette(appearance: .graphite))
        #expect(bar.countLabel.stringValue == "2 of 4")
        bar.nextButton.performClick(nil)
        bar.previousButton.performClick(nil)
        #expect(moves == [1, -1])
    }
}
