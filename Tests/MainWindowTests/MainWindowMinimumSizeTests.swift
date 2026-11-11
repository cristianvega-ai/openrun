import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct MainWindowMinimumSizeTests {
    /// The width that the screen of the window leaves for its content.
    private func room(of controller: MainWindowController) -> CGFloat {
        controller.window.screen.map { controller.window.contentRect(forFrameRect: $0.visibleFrame).width } ?? .infinity
    }

    @Test func theWindowHoldsTheVisibleListsAndTheContentAndGrowsForIt() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        #expect(controller.window.contentMinSize == NSSize(width: 160 + 240 + 360, height: 52 + 240))
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: 520, height: 300)))
        #expect(controller.window.contentMinSize == NSSize(width: 920, height: 352))
        controller.toggleProjectsList(nil)
        #expect(controller.window.contentMinSize.width == 760)
        controller.toggleProjectsList(nil)
        controller.updateContentMinimumSize(CGSize(width: 800, height: 300))
        let expected = min(1_200, room(of: controller))
        #expect(controller.window.contentMinSize.width == expected && controller.window.contentLayoutRect.width >= expected)
        #expect(controller.contentItem.minimumThickness == 800)
    }

    /// A program that sets a size below the minimum gets the minimum. The
    /// content fills the whole window, under the top row, so the size of
    /// the window and the minimum have one base.
    @Test func aSizeBelowTheMinimumComesBackToTheMinimum() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        let minimum = controller.window.contentMinSize
        controller.window.setContentSize(NSSize(width: 10, height: 10))
        #expect(controller.window.frame.size == minimum)
        controller.window.setFrame(NSRect(x: 100, y: 100, width: 300, height: 100), display: false)
        #expect(controller.window.frame.size == minimum)
    }
}
