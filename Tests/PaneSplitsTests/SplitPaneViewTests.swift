import AppKit
import Testing
import WindowLayout
@testable import PaneSplits

@MainActor @Suite struct SplitPaneViewTests {
    private let one = UUID(), two = UUID(), three = UUID()

    /// One session beside two stacked ones, with a third of the width for the first.
    private var pane: LayoutPane {
        let stacked = LayoutSplit(direction: .stacked, first: .session(two), second: .thread(three))
        return .split(LayoutSplit(direction: .sideBySide, fraction: 0.25, first: .session(one), second: .split(stacked)))
    }

    private func makeView() -> SplitPaneView {
        let view = SplitPaneView(pane: pane) { _ in NSView() }
        view.frame = NSRect(x: 0, y: 0, width: 801, height: 601)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func frame(_ leaf: UUID, in view: SplitPaneView) -> NSRect {
        view.view(of: leaf).map { $0.convert($0.bounds, to: view) } ?? .zero
    }

    @Test func theHalvesShareTheRoomAsTheLayoutTells() throws {
        let view = makeView()
        #expect(frame(one, in: view).width == 200 && frame(one, in: view).height == 601)
        #expect(frame(two, in: view).width == 600 && frame(two, in: view).height == 300 && frame(three, in: view).height == 300)
        #expect(frame(two, in: view).minX == 201 && frame(two, in: view).maxY > frame(three, in: view).maxY)
        // A new size keeps the shares.
        view.frame.size = NSSize(width: 401, height: 601)
        view.layoutSubtreeIfNeeded()
        #expect(frame(one, in: view).width == 100)
    }

    @Test func aLeafIsFoundByAViewInsideIt() throws {
        let inner = NSView()
        let view = SplitPaneView(pane: pane) { [two] leaf in
            let leafView = NSView()
            if leaf == two { leafView.addSubview(inner) }
            return leafView
        }
        #expect(view.leaf(holding: inner) == two && view.leaf(holding: view.view(of: one)) == one)
        #expect(view.leaf(holding: NSView()) == nil && view.leaf(holding: nil) == nil && view.view(of: UUID()) == nil)
    }

    @Test func aDividerThatTheUserMovedTellsItsNewShare() throws {
        let view = makeView()
        var changes: [(UUID, Double)] = []
        view.fractionChanged = { changes.append(($0, $1)) }
        let halves = try #require(view.subviews.first as? HalvesView)
        halves.setFraction(0.5)
        halves.mouseUp(with: NSEvent())
        view.layoutSubtreeIfNeeded()
        #expect(changes.count == 1 && changes.first?.0 == two && changes.first?.1 == 0.5 && frame(one, in: view).width == 400)
        // Each half stays in view.
        halves.setFraction(0.99)
        #expect(halves.fraction == 0.9)
    }

    @Test func theSmallestSizeAddsTheHalvesAlongTheirDirection() {
        let size = SplitPaneView.minimumSize(of: pane) { [one] in $0 == one ? CGSize(width: 300, height: 200) : CGSize(width: 320, height: 430) }
        #expect(size == CGSize(width: 300 + 320 + 1, height: 430 + 430 + 1))
        #expect(SplitPaneView.minimumSize(of: .session(one)) { _ in CGSize(width: 5, height: 6) } == CGSize(width: 5, height: 6))
    }
}
