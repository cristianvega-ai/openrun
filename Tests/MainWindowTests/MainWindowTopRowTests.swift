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
        let split = controller.splitController.view, full = split.frame.width, width = controller.frame(of: pane).minX
        for hides in [true, false] {
            controller.layout.projectsHidden = hides
            controller.updateTopRowSpaces()
            for step in 0...10 {
                // A hide moves the pane from its place to the edge; a show moves
                // it back. The content keeps its right edge at the window.
                let shift = width * CGFloat(hides ? step : 10 - step) / 10
                split.frame = NSRect(x: -shift, y: 0, width: full + shift, height: split.frame.height)
                controller.window.layoutIfNeeded()
                // A row moves its controls, but it never holds a pane open.
                #expect(abs(controller.frame(of: pane).minX - (width - shift)) <= 1, "hides \(hides), step \(step)")
                #expect(abs(start(of: row, controller) - expectedStart(of: pane, controller)) <= 1, "hides \(hides), step \(step)")
                #expect((row.leadingItems.arrangedSubviews.first === controller.listsButton) == hides, "hides \(hides), step \(step)")
            }
        }
    }

    @Test func atTheEndEachRowHasItsFinalPlace() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        let lights = controller.paneWindow.trafficLightsSpace
        controller.toggleProjectsList(nil)
        controller.window.layoutIfNeeded()
        #expect(start(of: controller.sessionsList.topRow, controller) == lights)
        #expect(start(of: controller.contentPane.topRow, controller) == controller.frame(of: controller.contentPane.view).minX + 16)
        controller.toggleProjectsList(nil)
        controller.window.layoutIfNeeded()
        #expect(start(of: controller.projectsList.topRow, controller) == lights)
        #expect(start(of: controller.sessionsList.topRow, controller) == controller.frame(of: controller.sessionsList.view).minX + 16)
    }

    /// A live check of the animation, beside the one that moves the panes by hand.
    @Test(.needsLiveDisplay)
    func theTitleOfAListStaysWithItsPaneInTheAnimation() async {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { false }
        controller.showWindow()
        await turns(seconds: 0.3)
        for direction in ["hide", "show"] {
            controller.toggleProjectsList(nil)
            let end = Date().addingTimeInterval(0.5)
            var worst: CGFloat = 0
            // AppKit lays out each step of the animation. A layout here would stop it.
            while Date() < end {
                worst = max(worst, abs(start(of: controller.sessionsList.topRow, controller) - expectedStart(of: controller.sessionsList.view, controller)))
                await turns(seconds: 0.01)
            }
            #expect(worst <= 3, "\(direction): \(worst) points away")
        }
    }
}
