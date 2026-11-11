import AppKit
import PaneAppearance
import Testing
@testable import MainWindow

/// The controls of a top row move with their pane in an animation, and
/// stop at the traffic lights, where a still layout puts them.
@MainActor @Suite(.serialized) struct MainWindowTopRowTests {
    /// Where a still layout puts the first control of a row: after the inset
    /// of its pane, or after the traffic lights when the pane reaches them.
    private func expectedStart(of pane: NSView, _ controller: MainWindowController) -> CGFloat {
        max(controller.frame(of: pane).minX + 16, controller.paneWindow.trafficLightsSpace)
    }
    private func start(of row: PaneTopRow, _ controller: MainWindowController) -> CGFloat {
        row.leadingItems.convert(row.leadingItems.bounds, to: controller.window.contentView).minX
    }

    /// The window sets the flags of the final layout before the panes move.
    /// Then the slide moves the sessions pane between its two places, which
    /// the test does with the frame of the split view, step by step.
    @Test func theControlsOfARowFollowTheirPaneAndStopAtTheTrafficLights() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        let row = controller.sessionsList.topRow, pane = controller.sessionsList.view
        let split = controller.splitController.view, width = controller.frame(of: pane).minX
        for hides in [true, false] {
            controller.layout.projectsHidden = hides
            controller.updateTopRowSpaces()
            for step in 0...10 {
                // A hide moves the pane from its place to the edge; a show moves it back.
                split.frame.origin.x = (hides ? -width : 0) * CGFloat(step) / 10 + (hides ? 0 : -width) * CGFloat(10 - step) / 10
                controller.window.layoutIfNeeded()
                #expect(abs(start(of: row, controller) - expectedStart(of: pane, controller)) <= 1, "hides \(hides), step \(step)")
                #expect((row.leadingItems.arrangedSubviews.first === controller.listsButton) == hides, "hides \(hides), step \(step)")
            }
        }
    }
}
