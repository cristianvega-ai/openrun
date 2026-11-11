import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct MainWindowControllerTests {
    @Test func thePanesLieSideBySideWithAShadowAtEachEdge() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        let (projects, sessions, content) = (controller.frame(of: controller.projectsList.view), controller.frame(of: controller.sessionsList.view), controller.frame(of: controller.contentPane.view))
        #expect(projects.minX == 0 && projects.width == 210 && sessions.width == 300 && content.maxX == 1_100)
        #expect(controller.sessionsShadow.frame.maxX == sessions.minX && controller.contentShadow.frame.maxX == content.minX)
        #expect(!controller.sessionsShadow.isHidden && !controller.contentShadow.isHidden)
        #expect(controller.sessionsShadow.superview === controller.window.contentView)
    }

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

    @Test func theThirdPaneShowsTheContentOfTheHost() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        let view = NSView()
        controller.showContent(PaneContent(view: view, title: "zsh", minimumSize: CGSize(width: 480, height: 300)))
        controller.updateContentTitle("vim")
        controller.updateContentMinimumSize(CGSize(width: 500, height: 300))
        #expect(view.superview === controller.contentPane.contentArea && controller.contentPane.titleLabel.stringValue == "vim")
        #expect(controller.contentPane.minimumSize.width == 500)
    }
}
