import AppKit
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite(.serialized, .isolatedThread) struct MinimumWindowSizeTests {
    /// A window at its minimum size, as a user's drag leaves it.
    private func makeSmallestWindow(_ attachment: FakeAttachment) async throws -> (SessionWindowController, TerminalView, NSRect) {
        let controller = try makeWindowController(attachment)
        await waitOnMainThread { controller.view?.visibleGridSize != nil }
        let view = try #require(controller.view)
        let screen = try #require(controller.window.screen).visibleFrame
        controller.window.setContentSize(controller.window.contentMinSize)
        view.layoutSubtreeIfNeeded()
        return (controller, view, screen)
    }

    @Test func largerTextGrowsAWindowAtItsMinimum() async throws {
        let (controller, view, _) = try await makeSmallestWindow(try FakeAttachment())
        defer { controller.window.close() }
        #expect(view.visibleGridSize == SessionWindowController.minimumGrid)
        let smallest = controller.window.contentMinSize
        view.increaseFontSize(nil)
        view.increaseFontSize(nil)
        view.layoutSubtreeIfNeeded()
        #expect(controller.window.contentMinSize.width > smallest.width)
        #expect(view.visibleGridSize == SessionWindowController.minimumGrid)
    }

    @Test func aWindowThatGrowsAtTheEdgeOfTheScreenStaysOnIt() async throws {
        let (controller, view, screen) = try await makeSmallestWindow(try FakeAttachment())
        defer { controller.window.close() }
        controller.window.setFrameOrigin(NSPoint(x: screen.maxX - controller.window.frame.width, y: screen.minY))
        let before = controller.window.frame
        view.increaseFontSize(nil)
        view.increaseFontSize(nil)
        view.layoutSubtreeIfNeeded()
        let after = controller.window.frame
        #expect(after.width > before.width && after.height > before.height)
        #expect(screen.insetBy(dx: -1, dy: -1).contains(after))
    }

    /// At the largest text, 60 columns do not fit the screen. The window then
    /// takes at most the screen, and the grid has fewer columns.
    @Test func theLargestTextKeepsTheWindowWithinTheScreen() async throws {
        let (controller, view, screen) = try await makeSmallestWindow(try FakeAttachment())
        defer { controller.window.close() }
        for _ in 0..<Int(FontSizeControl.range.upperBound - FontSizeControl.standard) { view.increaseFontSize(nil) }
        view.layoutSubtreeIfNeeded()
        #expect(screen.insetBy(dx: -1, dy: -1).contains(controller.window.frame))
        #expect(try #require(view.visibleGridSize).columns < SessionWindowController.minimumGrid.columns)
    }
}
