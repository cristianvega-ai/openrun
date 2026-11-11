import Foundation
import SessionConnection
import SessionProtocol
import Testing
@testable import SessionOverview

@Suite struct PendingChangesTests {
    private func changed(_ summary: SessionSummary, title: String) -> SessionSummary {
        var changed = summary
        changed.title = title
        return changed
    }

    @Test func onlyTheFirstEventOfABatchWakesTheMainThread() {
        let pending = PendingChanges()
        #expect(pending.add(.sessions([])))
        #expect(!pending.add(.sessionChanged(SessionOverviewTests.summary())))
        #expect(pending.takeAll().count == 2)
        #expect(pending.add(.closed))
        #expect(pending.takeAll() == [.closed])
        #expect(pending.takeAll().isEmpty)
    }

    @Test func aNewerChangeOfASessionReplacesTheOneThatWaits() {
        let pending = PendingChanges()
        let first = SessionOverviewTests.summary(), second = SessionOverviewTests.summary()
        _ = pending.add(.sessionChanged(first))
        _ = pending.add(.sessionChanged(second))
        #expect(!pending.add(.sessionChanged(changed(first, title: "new"))))
        #expect(pending.takeAll() == [.sessionChanged(changed(first, title: "new")), .sessionChanged(second)])
    }

    @Test func aNewerListReplacesTheOneThatWaits() {
        let pending = PendingChanges()
        let project = ProjectSummary(identifier: UUID(), name: nil, folder: "/work")
        let setting = SettingSummary(name: "theme", text: "graphite", isProtected: false)
        _ = pending.add(.projects([]))
        _ = pending.add(.settings([]))
        _ = pending.add(.projects([project]))
        _ = pending.add(.settings([setting]))
        #expect(pending.takeAll() == [.projects([project]), .settings([setting])])
    }

    @Test func aChangeAfterANewListOrAnEndComesAfterIt() {
        let pending = PendingChanges()
        let session = SessionOverviewTests.summary()
        _ = pending.add(.sessionChanged(session))
        _ = pending.add(.sessions([session]))
        _ = pending.add(.sessionChanged(changed(session, title: "later")))
        _ = pending.add(.sessionEnded(session.identifier))
        _ = pending.add(.sessionChanged(changed(session, title: "again")))
        #expect(pending.takeAll() == [
            .sessionChanged(session), .sessions([session]), .sessionChanged(changed(session, title: "later")),
            .sessionEnded(session.identifier), .sessionChanged(changed(session, title: "again")),
        ])
    }

    /// One hundred sessions that change one thousand times leave one hundred events.
    @Test func aFloodOfChangesStaysAsLongAsTheNumberOfSessions() {
        let pending = PendingChanges()
        let sessions = (0..<100).map { _ in SessionOverviewTests.summary() }
        for round in 0..<1_000 {
            for session in sessions { _ = pending.add(.sessionChanged(changed(session, title: "\(round)"))) }
        }
        let events = pending.takeAll()
        #expect(events == sessions.map { .sessionChanged(changed($0, title: "999")) })
    }
}
