import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import SessionProcess

/// A connection that watches, which keeps what it received.
private final class Watcher: Sendable {
    private let received = Mutex<[ServerMessage]>([])
    var key: ObjectIdentifier { ObjectIdentifier(self) }
    var send: SessionChangeFeed.Send { { message in self.received.withLock { $0.append(message) } } }
    var messages: [ServerMessage] { received.withLock { $0 } }
}

private func makeSummary(createdAt seconds: TimeInterval) -> SessionSummary {
    SessionSummary(identifier: UUID(), folder: "/", command: ["/bin/sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: seconds))
}

@Suite struct SessionChangeFeedTests {
    @Test func aWatcherGetsThePresentListAndThenEachChange() {
        let feed = SessionChangeFeed()
        let (newer, older) = (makeSummary(createdAt: 20), makeSummary(createdAt: 10))
        feed.add(newer)
        feed.add(older)
        let watcher = Watcher()
        feed.addWatcher(watcher.key, send: watcher.send)
        var titled = older
        titled.title = "vim"
        feed.change(titled)
        let third = makeSummary(createdAt: 30)
        feed.add(third)
        feed.end(older.identifier)
        #expect(watcher.messages == [
            .sessionList([older, newer]), .sessionChanged(titled), .sessionChanged(third), .sessionEnded(identifier: older.identifier),
        ])
    }

    /// A late change of a session that has ended must not bring it back,
    /// and a summary that did not change costs a watcher nothing.
    @Test func dropsAChangeThatTellsNothingNew() {
        let feed = SessionChangeFeed()
        let summary = makeSummary(createdAt: 1)
        feed.add(summary)
        let watcher = Watcher()
        feed.addWatcher(watcher.key, send: watcher.send)
        feed.change(summary)
        feed.end(summary.identifier)
        feed.end(summary.identifier)
        var late = summary
        late.isInProgress = true
        feed.change(late)
        #expect(watcher.messages == [.sessionList([summary]), .sessionEnded(identifier: summary.identifier)])
    }

    @Test func eachWatcherGetsTheChangesUntilItLeaves() {
        let feed = SessionChangeFeed()
        let (first, second) = (Watcher(), Watcher())
        feed.addWatcher(first.key, send: first.send)
        feed.addWatcher(second.key, send: second.send)
        let summary = makeSummary(createdAt: 1)
        feed.add(summary)
        feed.removeWatcher(first.key)
        feed.end(summary.identifier)
        #expect(first.messages == [.sessionList([]), .sessionChanged(summary)])
        #expect(second.messages == [.sessionList([]), .sessionChanged(summary), .sessionEnded(identifier: summary.identifier)])
    }

    /// The projects and the settings come right after the session list,
    /// and each later change comes in the order in which it happened.
    @Test func theProjectsAndTheSettingsFollowTheListInOrder() {
        let feed = SessionChangeFeed()
        let summary = makeSummary(createdAt: 1)
        feed.add(summary)
        let project = ProjectSummary(identifier: UUID(), name: nil, folder: "/work")
        let setting = SettingSummary(name: "theme", text: "graphite", isProtected: false)
        feed.replaceProjects([project])
        feed.replaceSettings([setting])
        let watcher = Watcher()
        feed.addWatcher(watcher.key, send: watcher.send)
        feed.replaceProjects([])
        var named = summary
        named.name = "build"
        feed.change(named)
        feed.replaceSettings([])
        #expect(watcher.messages == [
            .sessionList([summary]), .projectList([project]), .settingList([setting]),
            .projectList([]), .sessionChanged(named), .settingList([]),
        ])
    }
}
