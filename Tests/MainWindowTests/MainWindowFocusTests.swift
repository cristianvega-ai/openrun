import AppKit
import Testing
@testable import MainWindow

/// Keeps what the main window reports.
@MainActor
final class RecordingWindowHost: MainWindowDelegate {
    var events: [String] = []
    func mainWindowContentDidBecomeActive(_ window: MainWindowController) { events.append("active") }
    func mainWindowContentDidResignActive(_ window: MainWindowController) { events.append("inactive") }
    func mainWindowWillClose(_ window: MainWindowController) { events.append("close") }
}

@MainActor @Suite struct MainWindowFocusTests {
    @Test func theFocusMovesThroughTheVisiblePanesInTurn() {
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        let content = NSTextView()
        controller.showContent(PaneContent(view: NSScrollView(), title: "chat", minimumSize: .zero, focusView: content))
        controller.contentPane.content?.view.addSubview(content)
        let window = controller.window
        controller.focusNextPane(nil)
        #expect(window.firstResponder === controller.projectsList.focusView)
        controller.focusNextPane(nil)
        controller.focusNextPane(nil)
        #expect(window.firstResponder === content)
        controller.focusNextPane(nil)
        #expect(window.firstResponder === controller.projectsList.focusView)
        controller.toggleProjectsList(nil)
        controller.focusPreviousPane(nil)
        #expect(window.firstResponder === content)
        controller.focusPreviousPane(nil)
        #expect(window.firstResponder === controller.sessionsList.focusView)
    }

    /// A window that is not key never makes its content active, so the test
    /// checks the reports through the key state that AppKit gives it.
    @Test func theHostLearnsWhenTheContentIsActiveAndWhenTheWindowCloses() {
        let controller = makeMainWindow(), host = RecordingWindowHost()
        controller.delegate = host
        let content = NSTextView()
        controller.showContent(PaneContent(view: content, title: "zsh", minimumSize: .zero))
        controller.focusContent()
        #expect(controller.window.firstResponder === content)
        #expect(host.events == (controller.window.isKeyWindow ? ["active"] : []))
        controller.window.close()
        #expect(host.events.last == "close")
    }
}
