import AppKit
import Testing
@testable import TerminalView

@MainActor @Suite(.enabled(if: NSScreen.main != nil)) struct FocusInputTests {
    private func makeView() throws -> (view: TerminalView, window: NSWindow, delegate: RecordingDelegate) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, show(view), delegate)
    }

    private func post(_ name: Notification.Name, _ window: NSWindow) {
        NotificationCenter.default.post(name: name, object: window)
    }

    @Test func theCursorIsHollowWhileTheWindowIsNotKeyAndAProgramWithModeFocusReportsGetsThem() throws {
        let (view, window, delegate) = try makeView()
        defer { window.close() }
        #expect(!window.isKeyWindow && !view.renderer.isFocused)
        post(NSWindow.didBecomeKeyNotification, window)
        #expect(view.renderer.isFocused && delegate.takeSent() == "")
        view.terminal.write("\u{1B}[?1004h")
        post(NSWindow.didResignKeyNotification, window)
        #expect(!view.renderer.isFocused && delegate.takeSent() == "\u{1B}[O")
        post(NSWindow.didBecomeKeyNotification, window)
        #expect(view.renderer.isFocused && delegate.takeSent() == "\u{1B}[I")
    }

    @Test func aViewFollowsOnlyTheWindowThatHoldsIt() throws {
        let (view, window, delegate) = try makeView()
        let (_, other, _) = try makeView()
        defer { window.close(); other.close() }
        view.terminal.write("\u{1B}[?1004h")
        post(NSWindow.didBecomeKeyNotification, other)
        #expect(!view.renderer.isFocused && delegate.takeSent() == "")
        window.contentView = nil
        post(NSWindow.didBecomeKeyNotification, window)
        #expect(delegate.takeSent() == "")
    }
}
