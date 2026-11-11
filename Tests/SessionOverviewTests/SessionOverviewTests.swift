import Foundation
import SessionConnection
import SessionProtocol
import Testing
@testable import SessionOverview

@Suite struct SessionOverviewTests {
    static func summary(_ identifier: UUID = UUID(), folder: String = "/") -> SessionSummary {
        SessionSummary(identifier: identifier, folder: folder, command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func aChangeReplacesTheSessionOrAddsItAtTheEnd() {
        let first = Self.summary(), second = Self.summary()
        var overview = SessionOverview()
        overview.apply(.sessions([first]))
        overview.apply(.sessionChanged(second))
        var changed = first
        changed.title = "vim"
        overview.apply(.sessionChanged(changed))
        #expect(overview.sessions == [changed, second])
        #expect(overview.session(first.identifier)?.title == "vim")
    }

    @Test func anEndRemovesTheSessionAndANewListReplacesEverySession() {
        let first = Self.summary(), second = Self.summary()
        var overview = SessionOverview(sessions: [first, second])
        overview.apply(.sessionEnded(first.identifier))
        #expect(overview.sessions == [second])
        #expect(overview.session(first.identifier) == nil)
        overview.apply(.sessions([first]))
        #expect(overview.sessions == [first])
    }
}
