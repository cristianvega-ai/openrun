import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct MainWindowControllerTests {
    @Test func theWindowOpensWithTheWidthsThatTheUserLeft() {
        let defaults = temporaryDefaults()
        let first = makeMainWindow(defaults: defaults)
        first.splitController.splitView.setPosition(250, ofDividerAt: 0)
        first.window.close()
        #expect(PaneLayout.load(from: defaults).projectsWidth == 250)
        let second = makeMainWindow(defaults: defaults)
        defer { second.window.close() }
        #expect(second.projectsList.view.frame.width == 250 && second.sessionsList.view.frame.width == 300)
        #expect(abs(second.contentPane.view.frame.width - (1_100 - 250 - 300 - 2)) < 0.5)
    }
}
