import Foundation
import Testing
import WindowLayout

@Suite struct LayoutPaneSplitsTests {
    private let one = UUID(), two = UUID(), three = UUID()

    @Test func aNewPaneComesBesideItsLeafAsTheSecondHalf() {
        let pane = LayoutPane.session(one).splitting(one, with: .session(two), direction: .sideBySide)
        #expect(pane == .split(LayoutSplit(direction: .sideBySide, first: .session(one), second: .session(two))))
        // A split of the second leaf goes into the second half, and the reading order follows.
        let deeper = pane.splitting(two, with: .thread(three), direction: .stacked)
        #expect(deeper.leaves == [one, two, three] && deeper.sessions == [one, two] && deeper.threads == [three])
        #expect(deeper.splitting(UUID(), with: .session(UUID()), direction: .stacked) == deeper)
    }

    @Test func theLeafThatStartsTheSecondHalfNamesTheSplitOfAShare() {
        let inner = LayoutSplit(direction: .stacked, first: .session(two), second: .session(three))
        let pane = LayoutPane.split(LayoutSplit(direction: .sideBySide, first: .session(one), second: .split(inner)))
        guard case .split(let outer) = pane.settingFraction(0.3, ofSplitBefore: two), case .split(let kept) = outer.second else { Issue.record("no split"); return }
        #expect(outer.fraction == 0.3 && kept.fraction == 0.5)
        guard case .split(let same) = pane.settingFraction(0.8, ofSplitBefore: three), case .split(let changed) = same.second else { Issue.record("no split"); return }
        #expect(same.fraction == 0.5 && changed.fraction == 0.8)
        #expect(pane.settingFraction(0.1, ofSplitBefore: one) == pane && LayoutPane.session(one).settingFraction(0.1, ofSplitBefore: one) == .session(one))
    }

    @Test func aSplitOfARowTakesTheRowOfItsNewSessionAway() {
        var layout = WindowLayout()
        layout.follow(sessions: [one, two])
        layout.selectedRow = two
        let isSplit = layout.split(one, with: two, direction: .stacked)
        #expect(isSplit)
        #expect(layout.rows.map(\.identifier) == [one] && layout.rows.first?.pane.leaves == [one, two] && layout.selectedRow == one)
        // The rows follow the sessions as before: the new session has its place in the split.
        layout.follow(sessions: [one, two])
        #expect(layout.rows.count == 1)
        let refused = [layout.split(three, with: UUID(), direction: .stacked), layout.split(one, with: two, direction: .stacked)]
        #expect(refused == [false, false])
        // The other half takes the room of a half whose session ended.
        layout.follow(sessions: [two])
        #expect(layout.rows.first?.pane == .session(two) && layout.rows.first?.identifier == one)
    }
}
