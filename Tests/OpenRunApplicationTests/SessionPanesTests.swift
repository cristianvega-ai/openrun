import Foundation
import SessionPane
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite struct SessionPanesTests {
    private func makePanes() throws -> SessionPanes {
        let socket = try SocketLocation(path: NSTemporaryDirectory() + "no-session-process.socket")
        return SessionPanes { SessionPaneController(start: .runningSession($0), socket: socket) }
    }

    @Test func aSessionKeepsItsPaneUntilItCloses() throws {
        let panes = try makePanes()
        let session = UUID()
        let first = panes.pane(for: session)
        let again = panes.pane(for: session)
        #expect(first.isNew && !again.isNew && first.pane === again.pane)
        #expect(panes.existing(session) === first.pane && panes.session(of: first.pane) == session)
        panes.close(session)
        #expect(panes.existing(session) == nil && panes.all.isEmpty)
        #expect(panes.pane(for: session).isNew)
    }

    @Test func pastTheLimitThePaneThatWasShownLongestAgoCloses() throws {
        let panes = try makePanes()
        let sessions = (0..<SessionPanes.limit).map { _ in UUID() }
        for session in sessions { _ = panes.pane(for: session) }
        // The first session shows again, so the second one is the oldest now.
        _ = panes.pane(for: sessions[0])
        _ = panes.pane(for: UUID())
        #expect(panes.all.count == SessionPanes.limit)
        #expect(panes.existing(sessions[0]) != nil && panes.existing(sessions[1]) == nil)
        panes.closeAll()
        #expect(panes.all.isEmpty)
    }
}
