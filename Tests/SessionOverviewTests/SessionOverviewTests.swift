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

    @Test func theProjectsAndTheSettingsAreWholeLists() {
        let project = ProjectSummary(identifier: UUID(), name: "App", folder: "/work/app")
        var overview = SessionOverview()
        overview.apply(.projects([project]))
        overview.apply(.settings([SettingSummary(name: "font-size", text: "15", isProtected: false)]))
        #expect(overview.projects == [project])
        #expect(overview.settingText(named: "font-size") == "15")
        #expect(overview.settingText(named: "theme") == nil)
    }

    @Test func theThreadsFollowTheirListTheirChangesAndTheirEnds() {
        func thread(_ title: String?) -> ThreadSummary {
            ThreadSummary(identifier: UUID(), agent: "claude-code", folder: "/work", model: "opus", permissionMode: "default", title: title,
                          createdAt: Date(timeIntervalSince1970: 0), lastActivityAt: Date(timeIntervalSince1970: 0))
        }
        let first = thread(nil), second = thread("Notes")
        var overview = SessionOverview()
        overview.apply(.threads([first]))
        overview.apply(.threadChanged(second))
        var changed = first
        changed.state = "inProgress"
        overview.apply(.threadChanged(changed))
        #expect(overview.threads == [changed, second] && overview.thread(first.identifier)?.state == "inProgress")
        overview.apply(.threadEnded(first.identifier))
        #expect(overview.threads == [second] && overview.thread(first.identifier) == nil)
    }

    @Test func theEndOfAConnectionKeepsTheLastFacts() {
        var overview = SessionOverview(sessions: [Self.summary()])
        let before = overview
        overview.apply(.closed)
        overview.apply(.failed(.connectionClosed))
        #expect(overview == before)
    }
}
