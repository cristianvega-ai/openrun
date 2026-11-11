import AppKit
import Testing
@testable import MainWindow

/// The width of a list is the user's choice, made by a drag of its edge. A
/// squeeze can make a list narrower, but the list grows back when room comes back.
@MainActor @Suite struct MainWindowChosenWidthTests {
    @Test func aSqueezeKeepsTheChosenWidthsAndTheListsGrowBack() async throws {
        let defaults = temporaryDefaults()
        let controller = makeMainWindow(defaults: defaults)
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        controller.showContent(PaneContent(view: NSView(), title: "zsh", minimumSize: CGSize(width: 500, height: 300)))
        controller.window.setContentSize(NSSize(width: 1_280, height: 760))
        controller.window.layoutIfNeeded()
        let splitView = try #require(controller.splitController.splitView as? PaneSplitView)
        splitView.dragStarted?()
        splitView.setPosition(260, ofDividerAt: 0)
        splitView.setPosition(260 + splitView.dividerThickness + 340, ofDividerAt: 1)
        controller.window.layoutIfNeeded()
        splitView.dragEnded?()
        func expectWidths(_ projects: CGFloat, _ sessions: CGFloat, _ step: String) {
            let (shownProjects, shownSessions) = (controller.projectsList.view.frame.width, controller.sessionsList.view.frame.width)
            #expect(shownProjects == projects && shownSessions == sessions, "\(step): \(shownProjects), \(shownSessions)")
            let saved = PaneLayout.load(from: defaults)
            #expect(saved.projectsWidth == 260 && saved.sessionsWidth == 340, "\(step): saved \(saved.projectsWidth), \(saved.sessionsWidth)")
        }
        func change(_ step: () -> Void) async {
            step()
            await turns(seconds: 0.3)
            controller.window.layoutIfNeeded()
        }
        expectWidths(260, 340, "drag")
        await change { controller.window.setContentSize(NSSize(width: 10, height: 760)) }
        expectWidths(controller.projectsItem.minimumThickness, 240, "squeeze")
        await change { controller.toggleProjectsList(nil) }
        #expect(controller.sessionsList.view.frame.width == 340, "a hide gives the room back to the sessions list first")
        await change { controller.toggleProjectsList(nil) }
        expectWidths(controller.projectsItem.minimumThickness, 240, "show")
        await change { controller.window.setContentSize(NSSize(width: 1_400, height: 760)) }
        expectWidths(260, 340, "widen")
        let next = makeMainWindow(defaults: defaults)
        defer { next.window.close() }
        #expect(next.projectsList.view.frame.width == 260 && next.sessionsList.view.frame.width == 340)
    }
}
