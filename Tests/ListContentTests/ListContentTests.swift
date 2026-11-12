import Foundation
import ProjectsList
import SessionOverview
import SessionProtocol
import SessionsList
import Testing
import WindowLayout
@testable import ListContent

@Suite struct ListContentTests {
    let app = ProjectSummary(identifier: UUID(), name: nil, folder: "/Users/ana/Projects/app")
    let site = ProjectSummary(identifier: UUID(), name: "Web Site", folder: "/Users/ana/site")
    let gone = ProjectSummary(identifier: UUID(), name: nil, folder: nil)

    /// Three sessions: one in the app with an alert, one in the site, and one outside every project.
    private func content(inView: UUID? = nil) -> (content: ListContent, sessions: [SessionSummary]) {
        var sessions = (0..<3).map { SessionRowFactsTests.session(created: Double($0)) }
        (sessions[0].projectIdentifier, sessions[1].projectIdentifier, sessions[2].projectIdentifier) = (app.identifier, site.identifier, UUID())
        sessions[0].alert = SessionAlert(text: "Allow?", raisedAt: Date(), source: .terminalNotification)
        sessions[2].alert = SessionAlert(text: "Done", raisedAt: Date(), source: .notifyCommand)
        var layout = WindowLayout()
        layout.follow(sessions: sessions.map(\.identifier))
        let overview = SessionOverview(sessions: sessions, projects: [app, site, gone])
        return (ListContent(overview: overview, layout: layout, inView: inView, home: "/Users/ana"), sessions)
    }

    @Test func theFirstPaneShowsTheProjectsAndTheCountsOfTheRowsThatNeedTheUser() {
        let projects = content().content.projects
        #expect(projects.projects == [
            ProjectDisplay(identifier: app.identifier, name: "app", folder: "~/Projects/app", attentionCount: 1),
            ProjectDisplay(identifier: site.identifier, name: "Web Site", folder: "~/site"),
            ProjectDisplay(identifier: gone.identifier, name: "Project", folder: "No folder on this Mac"),
        ])
        #expect(projects.needsYouCount == 2)
    }

    @Test func eachEntryShowsItsRowsInTheOrderOfTheUser() {
        let (content, sessions) = content()
        let identifiers = sessions.map(\.identifier)
        #expect(content.rows(of: .allSessions).map(\.identifier) == identifiers.reversed())
        #expect(content.rows(of: .needsYou).map(\.identifier) == [identifiers[2], identifiers[0]])
        #expect(content.rows(of: .project(app.identifier)).map(\.identifier) == [identifiers[0]])
        #expect(content.rows(of: .project(gone.identifier)).isEmpty)
        // A session whose project the list does not hold is outside every project. It tells its folder.
        #expect(content.rows(of: .allSessions).first?.folder.isEmpty == false)
    }

    @Test func aRowTellsItsPlaceByItsProject() {
        var sessions = (0..<3).map { SessionRowFactsTests.session(created: Double($0)) }
        for index in sessions.indices { sessions[index].projectIdentifier = app.identifier }
        (sessions[0].folder, sessions[0].currentFolder) = ("/Users/ana/Projects/app", "/Users/ana/Projects/app/Sources/Core")
        (sessions[1].folder, sessions[1].currentFolder, sessions[1].branch) = ("/Users/ana/Projects/app", nil, "main")
        // The program of the third session went to a folder outside the project.
        (sessions[2].folder, sessions[2].currentFolder) = ("/Users/ana/Projects/app", "/tmp/build")
        var layout = WindowLayout()
        layout.follow(sessions: sessions.map(\.identifier))
        let content = ListContent(overview: SessionOverview(sessions: sessions, projects: [app]), layout: layout, inView: nil, home: "/Users/ana")
        // A list of many projects names the project. The list of the project itself does not.
        #expect(content.rows(of: .allSessions).map(\.folder) == ["/tmp/build", "app", "app/Sources/Core"])
        #expect(content.rows(of: .project(app.identifier)).map(\.folder) == ["/tmp/build", "", "Sources/Core"])
        // A terminal at the root of its project with no branch keeps its folder, so its second line is not empty.
        sessions[1].branch = nil
        let plain = ListContent(overview: SessionOverview(sessions: sessions, projects: [app]), layout: layout, inView: nil, home: "/Users/ana")
        #expect(plain.rows(of: .project(app.identifier))[1].folder == "~/Projects/app")
    }

    @Test func theSessionInViewCountsAsNoRowThatNeedsTheUser() {
        let (first, sessions) = content()
        let layout = WindowLayout(rows: sessions.map { LayoutRow(session: $0.identifier) })
        let overview = SessionOverview(sessions: sessions, projects: [app, site, gone])
        let projects = ListContent(overview: overview, layout: layout, inView: sessions[0].identifier, home: "/Users/ana").projects
        #expect(first.projects.needsYouCount == 2)
        #expect(projects.needsYouCount == 1 && projects.projects[0].attentionCount == 0)
    }

    @Test func aThreadShowsAsARowOfItsAgentWithItsStateAndItsProject() {
        var thread = ThreadSummary(identifier: UUID(), agent: "claude-code", folder: "/Users/ana/Projects/app", model: "claude-opus-5-5", permissionMode: "default",
                                   title: "Repair the resize", createdAt: Date(timeIntervalSince1970: 10), lastActivityAt: Date(timeIntervalSince1970: 90))
        (thread.state, thread.projectIdentifier) = ("needsUser", app.identifier)
        let layout = WindowLayout(rows: [LayoutRow(thread: thread.identifier)])
        func content(inView: UUID? = nil) -> ListContent {
            ListContent(overview: SessionOverview(projects: [app], threads: [thread]), layout: layout, inView: inView, home: "/Users/ana")
        }
        let row = content().rows(of: .project(app.identifier)).first
        #expect(row == SessionRowDisplay(
            identifier: thread.identifier, title: "Repair the resize", folder: "", kind: .agentThread(agent: "Claude Code", model: "Opus", account: nil),
            alert: "Waits for your answer", lastActivity: thread.lastActivityAt, startTime: thread.createdAt))
        // The list of its own project shows the model alone, and a list of many projects names the project.
        #expect(content().rows(of: .allSessions).first?.folder == "app" && content().rows(of: .needsYou).first?.folder == "app")
        #expect(content().projects.needsYouCount == 1 && content(inView: thread.identifier).projects.needsYouCount == 0)
        thread.name = "Resize"
        thread.state = "inProgress"
        #expect(ThreadRowFacts.title(of: thread) == "Resize" && ThreadRowFacts.shortModelName("gpt-6") == "gpt-6")
        #expect(ThreadRowFacts.modelTitle("opus") == "Opus" && ThreadRowFacts.modelTitle("claude-opus-5-5") == "claude-opus-5-5")
        // The usage of the account shows with the time of its reading, because a reading can be old.
        var used = thread
        #expect(ThreadRowFacts.usageText(of: used) == nil && ThreadRowFacts.limitResetTime(of: used) == nil)
        let reset = Date(timeIntervalSince1970: 86_400)
        used.usageWindows = [
            ThreadUsageWindow(name: "five_hour", lengthInMinutes: 300, usedFraction: 0.124), ThreadUsageWindow(name: "unknown"),
            ThreadUsageWindow(name: "seven_day", lengthInMinutes: 10_080, usedFraction: 1, resetTime: reset, status: "rejected"),
        ]
        used.usageReadAt = Date(timeIntervalSince1970: 14 * 3600 + 32 * 60)
        let text = ThreadRowFacts.usageText(of: used, timeZone: TimeZone(identifier: "UTC")!)
        #expect(text?.hasPrefix("5 h 12% used, Week 100% used · read ") == true && text?.contains("32") == true)
        #expect(ThreadRowFacts.limitResetTime(of: used) == .some(reset))
        #expect(ThreadRowFacts.windowName(ThreadUsageWindow(name: "daily", lengthInMinutes: 1_440)) == "Day" && ThreadRowFacts.windowName(ThreadUsageWindow(name: "burst", lengthInMinutes: 90)) == "90 min")
        #expect(["plan", "dontAsk", "default", "acceptEdits", "auto", "later"].map(ThreadRowFacts.permissionModeTitle)
            == ["Plan Only", "Rules Only", "Ask First", "Accept Edits", "Auto", "later"])
        #expect(["readOnly", "workspaceWrite"].map(ThreadRowFacts.permissionModeTitle) == ["Read Only", "Write in Folder"])
        #expect(ThreadRowFacts.modelTitle("default") == "Default Model" && ThreadRowFacts.agentName("codex") == "Codex")
        #expect(ThreadRowFacts.display(of: layout.rows[0], thread: thread, inView: false, home: "/").isInProgress)
        // A thread that the overview does not hold gives no row.
        #expect(ListContent(overview: SessionOverview(), layout: layout, inView: nil).rows(of: .allSessions).isEmpty)
    }

    @Test func theTitleOfAnEntryIsItsName() {
        let content = content().content
        #expect(content.title(of: .allSessions) == "All Projects" && content.title(of: .needsYou) == "Needs You")
        #expect(content.title(of: .project(site.identifier)) == "Web Site")
        // The second pane tells where new work starts, and names an empty project.
        #expect(content.place(of: .project(site.identifier)) == "In Web Site" && content.place(of: .allSessions) == "In Your Home Folder")
        #expect(content.emptyMessage(of: .project(site.identifier)) == "Nothing in Web Site Yet" && content.emptyMessage(of: .needsYou) == "Nothing Needs You")
        #expect(content.emptyMessage(of: .allSessions) == nil)
        #expect(content.title(of: .project(app.identifier)) == "app" && content.title(of: .project(UUID())) == "")
    }
}
