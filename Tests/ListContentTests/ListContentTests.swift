import Foundation
import ProjectsList
import SessionOverview
import SessionProtocol
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
        #expect(projects.needsYouCount == 2 && projects.noProjectAttentionCount == 1)
    }

    @Test func eachEntryShowsItsRowsInTheOrderOfTheUser() {
        let (content, sessions) = content()
        let identifiers = sessions.map(\.identifier)
        #expect(content.rows(of: .allSessions).map(\.identifier) == identifiers.reversed())
        #expect(content.rows(of: .needsYou).map(\.identifier) == [identifiers[2], identifiers[0]])
        #expect(content.rows(of: .project(app.identifier)).map(\.identifier) == [identifiers[0]])
        #expect(content.rows(of: .project(gone.identifier)).isEmpty)
        // A session whose project the list does not hold is outside every project.
        #expect(content.rows(of: .noProject).map(\.identifier) == [identifiers[2]])
    }

    @Test func theSessionInViewCountsAsNoRowThatNeedsTheUser() {
        let (first, sessions) = content()
        let layout = WindowLayout(rows: sessions.map { LayoutRow(session: $0.identifier) })
        let overview = SessionOverview(sessions: sessions, projects: [app, site, gone])
        let projects = ListContent(overview: overview, layout: layout, inView: sessions[0].identifier, home: "/Users/ana").projects
        #expect(first.projects.needsYouCount == 2)
        #expect(projects.needsYouCount == 1 && projects.projects[0].attentionCount == 0)
    }

    @Test func theTitleOfAnEntryIsItsName() {
        let content = content().content
        #expect(content.title(of: .allSessions) == "All Sessions" && content.title(of: .needsYou) == "Needs You")
        #expect(content.title(of: .noProject) == "No Project" && content.title(of: .project(site.identifier)) == "Web Site")
        #expect(content.title(of: .project(app.identifier)) == "app" && content.title(of: .project(UUID())) == "")
    }
}
