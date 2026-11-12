import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct ContentPaneControllerTests {
    @Test func thePaneShowsOneContentOrTheEmptyState() {
        let pane = ContentPaneController()
        var changes = 0
        pane.minimumSizeChanged = { changes += 1 }
        #expect(!pane.emptyLabel.isHidden && pane.minimumSize == ContentPaneController.emptyMinimumSize)
        let switchButton = NSButton(), first = NSView(), second = NSView()
        pane.show(PaneContent(view: first, title: "Repair the resize", minimumSize: CGSize(width: 520, height: 300), topRowItems: [switchButton]))
        #expect(first.superview === pane.contentArea && pane.emptyLabel.isHidden && pane.titleLabel.stringValue == "Repair the resize")
        #expect(pane.topRow.trailingItems.arrangedSubviews == [switchButton] && pane.minimumSize.width == 520)
        pane.updateTitle("vim")
        pane.updateMinimumSize(CGSize(width: 600, height: 320))
        #expect(pane.titleLabel.stringValue == "vim" && pane.content?.title == "vim" && pane.minimumSize.width == 600)
        pane.show(PaneContent(view: second, title: "zsh", minimumSize: .zero))
        #expect(first.superview == nil && switchButton.superview == nil && second.superview === pane.contentArea)
        pane.show(nil)
        #expect(second.superview == nil && !pane.emptyLabel.isHidden && pane.titleLabel.stringValue.isEmpty && changes == 4)
    }

    /// A session that gets a split: its view is one half of the new content.
    @Test func aViewThatMovedIntoTheNewContentKeepsItsNewPlace() {
        let pane = ContentPaneController()
        let session = NSView(), split = NSView()
        pane.show(PaneContent(view: session, title: "zsh", minimumSize: .zero))
        split.addSubview(session)
        pane.show(PaneContent(view: split, title: "zsh", minimumSize: .zero))
        #expect(session.superview === split && split.superview === pane.contentArea)
        // The way back takes the view out of the split.
        pane.show(PaneContent(view: session, title: "zsh", minimumSize: .zero))
        #expect(session.superview === pane.contentArea && split.superview == nil)
    }
}
