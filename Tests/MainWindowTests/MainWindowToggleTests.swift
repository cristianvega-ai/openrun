import AppKit
import Testing
@testable import MainWindow
@testable import SessionPane

/// Each animated toggle of the lists at and near the minimum width: the
/// window stays on its screen and at its minimum, the content gets the
/// final width, and the session gets at most one size.
@MainActor @Suite(.serialized) struct MainWindowToggleTests {
    enum Toggle: CaseIterable { case projects, sessions, both }
    enum Width: CaseIterable { case minimum, onePointAbove, betweenMinimums }

    private func setHidden(_ toggle: Toggle, _ hidden: Bool, in controller: MainWindowController) {
        controller.reducesMotion = { true }
        let (projects, sessions) = (toggle == .sessions ? false : hidden, toggle == .projects ? false : hidden)
        if controller.projectsItem.isCollapsed != projects { controller.toggleProjectsList(nil) }
        if controller.sessionsItem.isCollapsed != sessions { controller.toggleSessionsList(nil) }
        controller.reducesMotion = { false }
    }

    private func finalMinimumWidth(_ toggle: Toggle, _ controller: MainWindowController) -> CGFloat {
        var layout = controller.layout
        if toggle != .sessions { layout.projectsHidden.toggle() }
        if toggle != .projects { layout.sessionsHidden.toggle() }
        let room = controller.window.screen.map { controller.window.contentRect(forFrameRect: $0.visibleFrame).width } ?? .infinity
        return min(layout.minimumWidth(content: controller.contentPane.minimumSize.width), room)
    }

    /// Waits until no hold is on and the count of sizes stays the same for
    /// half a second, because under load a size can go out late.
    private func settle(_ controller: MainWindowController, _ pane: SessionPaneController) async {
        await turns(seconds: 5) { !controller.contentPane.isHoldingWidth }
        var count = -1
        while count != pane.sentSizeRequests {
            count = pane.sentSizeRequests
            await turns(seconds: 0.5)
        }
    }

    private func check(_ toggle: Toggle, fromHidden hidden: Bool, at width: Width, _ controller: MainWindowController, _ pane: SessionPaneController) async {
        let name = "\(toggle) from hidden \(hidden) at \(width)"
        setHidden(toggle, hidden, in: controller)
        let (start, end) = (controller.window.contentMinSize.width, finalMinimumWidth(toggle, controller))
        let target: CGFloat = switch width {
        case .minimum: 10
        case .onePointAbove: start + 1
        case .betweenMinimums: max(start, ((start + end) / 2).rounded())
        }
        controller.window.setContentSize(NSSize(width: target, height: 10))
        await settle(controller, pane)
        let (before, gridBefore) = (pane.sentSizeRequests, pane.terminalView?.gridSize)
        if toggle != .sessions { controller.toggleProjectsList(nil) }
        if toggle != .projects { controller.toggleSessionsList(nil) }
        await settle(controller, pane)
        if pane.sentSizeRequests > before { await turns(seconds: 10) { pane.terminalView?.gridSize != gridBefore } }
        let window = controller.window
        let content = window.contentRect(forFrameRect: window.frame).size
        #expect(window.screen.map { $0.visibleFrame.contains(window.frame) } ?? true, "\(name)")
        #expect(window.contentMinSize.width == end && content.width >= end && content.height >= window.contentMinSize.height, "\(name)")
        #expect(pane.paneView.frame.width == controller.contentPane.contentArea.frame.width, "\(name)")
        let changed = pane.terminalView?.gridSize != gridBefore
        #expect(pane.sentSizeRequests - before == (changed ? 1 : 0), "\(name): \(pane.sentSizeRequests - before) sizes, grid \(String(describing: gridBefore)) to \(String(describing: pane.terminalView?.gridSize))")
    }

    @Test func everyToggleNearTheMinimumKeepsTheWindowWhole() async throws {
        try await withHostedSession { controller, pane in
            for toggle in Toggle.allCases {
                for hidden in [false, true] {
                    for width in Width.allCases { await check(toggle, fromHidden: hidden, at: width, controller, pane) }
                }
            }
        }
    }

    /// A larger text size makes a larger minimum, which the host forwards.
    @Test func everyToggleAtTheMinimumWithALargerTextSize() async throws {
        try await withHostedSession { controller, pane in
            for _ in 0..<3 { pane.terminalView?.increaseFontSize(nil) }
            controller.updateContentMinimumSize(pane.minimumSize)
            await turns(seconds: 1)
            for toggle in Toggle.allCases {
                for hidden in [false, true] { await check(toggle, fromHidden: hidden, at: .minimum, controller, pane) }
            }
        }
    }
}
