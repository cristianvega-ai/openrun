import AppKit
import Testing
@testable import MainWindow

/// The width of a list is the user's choice, made by a drag of its edge. A
/// squeeze can make a list narrower, but it does not change the choice.
@MainActor @Suite struct MainWindowChosenWidthTests {
    @Test func aSqueezeKeepsTheChosenWidths() async throws {
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
        func expectSaved(_ step: String) {
            let saved = PaneLayout.load(from: defaults)
            #expect(saved.projectsWidth == 260 && saved.sessionsWidth == 340, "\(step): saved \(saved.projectsWidth), \(saved.sessionsWidth)")
        }
        func change(_ step: () -> Void) async {
            step()
            await turns(seconds: 0.3)
            controller.window.layoutIfNeeded()
        }
        #expect(controller.projectsList.view.frame.width == 260 && controller.sessionsList.view.frame.width == 340)
        expectSaved("drag")
        await change { controller.window.setContentSize(NSSize(width: 10, height: 760)) }
        expectSaved("squeeze")
        await change { controller.toggleProjectsList(nil) }
        expectSaved("hide")
        await change { controller.toggleProjectsList(nil) }
        expectSaved("show")
        let next = makeMainWindow(defaults: defaults)
        defer { next.window.close() }
        #expect(next.projectsList.view.frame.width == 260 && next.sessionsList.view.frame.width == 340)
    }
}
