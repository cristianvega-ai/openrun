import AppKit
import Foundation
import SessionProtocol
import Testing
@testable import SessionPane

@MainActor @Suite struct SessionPaneFailureTests {
    private struct Refusal: Error {}

    /// A pane that a host keeps out of its window, such as for a row that the
    /// user does not look at, still gets its failure to the user.
    @Test func aFailureWithoutAWindowReachesTheHostAndShowsInTheNextWindow() async throws {
        _ = NSApplication.shared
        let pane = SessionPaneController(start: .runningSession(UUID()), socket: try SocketLocation(path: "/tmp/openrun-test-none.sock"))
        let host = RecordingHost()
        pane.delegate = host
        pane.connect = { _, _, _ in throw Refusal() }
        var questions: [UserQuestion] = []
        pane.ask = { question, _ in questions.append(question); return true }
        pane.paneView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        pane.attach()
        await waitOnMainThread { !host.failures.isEmpty }
        await waitOnMainThread(seconds: 0.2) { false }
        #expect(host.failures.count == 1 && host.failures[0].contains("Could not connect") && host.ends == 0 && questions.isEmpty)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(pane.paneView)
        await waitOnMainThread { host.ends == 1 }
        #expect(host.ends == 1 && questions.count == 1 && host.failures.count == 1)
        if case .connectionFailure(let detail) = questions.first { #expect(detail == host.failures[0]) } else { Issue.record("No failure question") }
    }
}
