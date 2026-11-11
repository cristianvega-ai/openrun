import Foundation
import SessionProtocol
import SessionsList
import Testing
import WindowLayout
@testable import ListContent

@Suite struct SessionRowFactsTests {
    static let home = "/Users/ana"

    static func session(_ identifier: UUID = UUID(), folder: String = "/Users/ana/Projects/openrun", created: TimeInterval = 100) -> SessionSummary {
        SessionSummary(identifier: identifier, folder: folder, command: ["/bin/zsh"], size: SessionSize(columns: 80, rows: 24),
                       createdAt: Date(timeIntervalSince1970: created))
    }

    /// The row of the sessions as splits of one row, in their order.
    static func display(_ sessions: [SessionSummary], inView: UUID? = nil) -> SessionRowDisplay? {
        let panes = sessions.map { LayoutPane.session($0.identifier) }
        let pane = panes.dropFirst().reduce(panes[0]) { .split(LayoutSplit(direction: .sideBySide, first: $0, second: $1)) }
        let row = LayoutRow(identifier: sessions[0].identifier, pane: pane)
        return SessionRowFacts.display(of: row, sessions: { identifier in sessions.first { $0.identifier == identifier } }, inView: inView, home: home)
    }

    @Test func theTitleIsTheNameThenTheTitleOfTheProgramThenTheProgramAndTheFolder() {
        var session = Self.session()
        #expect(Self.display([session])?.title == "zsh — openrun")
        session.foregroundProgram = "vim"
        session.currentFolder = Self.home
        #expect(Self.display([session])?.title == "vim — ~")
        session.title = "notes.txt"
        #expect(Self.display([session])?.title == "notes.txt")
        session.name = "Release"
        #expect(Self.display([session])?.title == "Release")
        session.name = ""
        #expect(Self.display([session])?.title == "notes.txt")
    }

    @Test func theRowShowsTheCurrentFolderTheBranchAndTheWork() {
        var session = Self.session()
        #expect(Self.display([session]) == SessionRowDisplay(
            identifier: session.identifier, title: "zsh — openrun", folder: "~/Projects/openrun", kind: .terminal,
            lastActivity: session.createdAt, startTime: session.createdAt))
        (session.currentFolder, session.branch, session.isInProgress) = ("/tmp/build", "main", true)
        let row = Self.display([session])
        #expect(row?.folder == "/tmp/build" && row?.branch == "main" && row?.isInProgress == true)
    }

    @Test func anAlertShowsItsTextAndTheSessionInViewShowsNone() {
        var session = Self.session()
        session.alert = SessionAlert(text: "Allow the edit?", raisedAt: Date(), source: .terminalNotification)
        #expect(Self.display([session])?.alert == "Allow the edit?")
        #expect(Self.display([session], inView: session.identifier)?.alert == nil)
        session.alert = SessionAlert(text: "", raisedAt: Date(), source: .bell)
        #expect(Self.display([session])?.alert == "Needs your attention")
    }

    @Test func aRowOfSplitsTakesItsTitleFromTheFirstAndItsMarksFromAll() {
        var (first, second) = (Self.session(created: 100), Self.session(folder: "/tmp", created: 200))
        second.isInProgress = true
        second.alert = SessionAlert(text: "Done", raisedAt: Date(), source: .notifyCommand)
        second.lastOutputAt = Date(timeIntervalSince1970: 900)
        first.lastInputAt = Date(timeIntervalSince1970: 500)
        let row = Self.display([first, second], inView: first.identifier)
        #expect(row?.identifier == first.identifier && row?.title == "zsh — openrun" && row?.folder == "~/Projects/openrun")
        #expect(row?.isInProgress == true && row?.alert == "Done")
        #expect(row?.lastActivity == Date(timeIntervalSince1970: 900) && row?.startTime == first.createdAt)
    }

    @Test func aRowWithNoSessionThatRunsGivesNothing() {
        let row = LayoutRow(session: UUID())
        #expect(SessionRowFacts.display(of: row, sessions: { _ in nil }, inView: nil, home: Self.home) == nil)
    }
}
