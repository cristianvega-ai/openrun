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
        #expect(controller.window.contentMinSize == NSSize(width: expectedMinimumWidth(of: controller, content: 360), height: 52 + 240))
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: 520, height: 300)))
        #expect(controller.window.contentMinSize == NSSize(width: expectedMinimumWidth(of: controller, content: 520), height: 352))
        controller.toggleProjectsList(nil)
        #expect(controller.window.contentMinSize.width == expectedMinimumWidth(of: controller, content: 520))
        controller.toggleProjectsList(nil)
        controller.updateContentMinimumSize(CGSize(width: 800, height: 300))
        let expected = min(expectedMinimumWidth(of: controller, content: 800), room(of: controller))
        #expect(controller.window.contentMinSize.width == expected && controller.window.contentLayoutRect.width >= expected)
        #expect(controller.contentItem.minimumThickness == 800)
    }

    /// A program that sets a size below the minimum gets at least the minimum soon after. The
    /// content fills the whole window, under the top row, so the size of
    /// the window and the minimum have one base.
    @Test func aSizeBelowTheMinimumComesBackToTheMinimum() async {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        let minimum = controller.window.contentMinSize
        controller.window.setContentSize(NSSize(width: 10, height: 10))
        await turns(seconds: 0.2)
        #expect(controller.window.frame.width >= minimum.width && controller.window.frame.height >= minimum.height)
        controller.window.setFrame(NSRect(x: 100, y: 100, width: 300, height: 100), display: false)
        await turns(seconds: 0.2)
        #expect(controller.window.frame.width >= minimum.width && controller.window.frame.height >= minimum.height)
    }

    /// The minimum counts the dividers and the top row of the first pane,
    /// which holds the traffic lights. Else AppKit grows the window past it.
    @Test func theWindowAtItsMinimumHasNoRoomToSpare() async {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: 500, height: 300)))
        for (projects, sessions) in [(false, false), (true, false), (false, true), (true, true)] {
            if controller.projectsItem.isCollapsed != projects { controller.toggleProjectsList(nil) }
            if controller.sessionsItem.isCollapsed != sessions { controller.toggleSessionsList(nil) }
            controller.window.setContentSize(NSSize(width: 10, height: 10))
            await turns(seconds: 0.3)
            controller.window.layoutIfNeeded()
            let width = controller.window.contentRect(forFrameRect: controller.window.frame).width
            #expect(width == controller.window.contentMinSize.width, "hidden \(projects) \(sessions): \(width)")
            #expect(controller.contentPane.view.frame.width == 500, "hidden \(projects) \(sessions)")
        }
    }

    /// An animated show of a list at the minimum width once ended the app
    /// with an exception: a check of the minimum inside the layout pass of
    /// the animation asked for another pass without end.
    @Test func anAnimatedShowAtTheMinimumGrowsTheWindow() async {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: 500, height: 300)))
        controller.showWindow()
        controller.reducesMotion = { true }
        controller.toggleSessionsList(nil)
        controller.reducesMotion = { false }
        controller.window.setContentSize(NSSize(width: 10, height: 10))
        await turns(seconds: 0.3)
        controller.toggleSessionsList(nil)
        await turns(seconds: 1)
        let expected = expectedMinimumWidth(of: controller, content: 500)
        #expect(controller.window.contentMinSize.width == expected && controller.window.frame.width >= expected)
    }

    /// A show near the minimum takes the room of the list from the content
    /// where it can. The window grows only to the new minimum. It once grew
    /// to the minimum, and AppKit then added the width of the list again.
    @Test(arguments: [false, true]) func aShowNearTheMinimumGrowsOnlyToTheNewMinimum(reducesMotion: Bool) async {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: 500, height: 300)))
        controller.showWindow()
        controller.reducesMotion = { true }
        controller.toggleSessionsList(nil)
        controller.window.setContentSize(NSSize(width: 10, height: 400))
        await turns(seconds: 0.3)
        controller.reducesMotion = { reducesMotion }
        controller.toggleSessionsList(nil)
        await turns(seconds: 1.5)
        let width = controller.window.contentRect(forFrameRect: controller.window.frame).width
        #expect(width == controller.window.contentMinSize.width && controller.contentPane.view.frame.width == 500, "\(width)")
    }

    /// With a content as wide as the screen, the screen limits the window.
    @Test func aShowWithAMinimumAsWideAsTheScreenStaysOnTheScreen() async throws {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.showWindow()
        let screen = try #require(controller.window.screen).visibleFrame
        controller.reducesMotion = { true }
        controller.toggleSessionsList(nil)
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: room(of: controller), height: 300)))
        await turns(seconds: 0.3)
        controller.reducesMotion = { false }
        controller.toggleSessionsList(nil)
        await turns(seconds: 1.5)
        let frame = controller.window.frame
        #expect(screen.contains(frame) && frame.width == screen.width, "\(frame) on \(screen)")
    }

    /// A new screen sets the minimum again, after the pass that moved the window.
    @Test func aNewScreenSetsTheMinimumAgainLater() async {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        let minimum = controller.window.contentMinSize
        controller.window.contentMinSize = NSSize(width: 100, height: 100)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: controller.window)
        #expect(controller.window.contentMinSize.width == 100)
        await turns(seconds: 0.2)
        #expect(controller.window.contentMinSize == minimum)
    }
}
