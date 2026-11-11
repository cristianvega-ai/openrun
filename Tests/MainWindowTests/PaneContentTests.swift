import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct PaneContentTests {
    @Test func theContentKeepsItsViewControllerAndFocusesItsViewByDefault() {
        let controller = NSViewController()
        controller.view = NSView()
        let field = NSTextField()
        let content = PaneContent(viewController: controller, title: "zsh", minimumSize: CGSize(width: 500, height: 300))
        #expect(content.view === controller.view && content.viewController === controller && content.focusView === controller.view)
        let other = PaneContent(view: NSView(), title: "chat", minimumSize: .zero, topRowItems: [NSButton()], focusView: field)
        #expect(other.focusView === field && other.viewController == nil && other.topRowItems.count == 1)
    }
}
