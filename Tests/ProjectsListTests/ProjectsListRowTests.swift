import Foundation
import Testing
@testable import ProjectsList

@Suite struct ProjectsListRowTests {
    private let first = UUID(), second = UUID()

    @Test func theProjectsComeLastUnderTheirHeading() {
        let content = ProjectsListContent(
            projects: [ProjectDisplay(identifier: first, name: "openrun", folder: "/p/openrun", attentionCount: 2),
                       ProjectDisplay(identifier: second, name: "website", folder: "/p/website")],
            needsYouCount: 3)
        let rows = ProjectsListRow.rows(for: content)
        #expect(rows.map(\.entry) == [.allSessions, .needsYou, nil, .project(first), .project(second)])
        #expect(rows.map(\.name) == ["All Projects", "Needs You", "Projects", "openrun", "website"])
        #expect(rows.map(\.attentionCount) == [0, 3, 0, 2, 0] && rows[2].kind == .heading)
        #expect(rows[3].help == "/p/openrun" && rows[3].projectIdentifier == first && rows[1].projectIdentifier == nil)
        #expect(ProjectsListRow.firstProjectRow == 3)
    }

    @Test func theHeadingHasAHintWhileTheUserHasNoProject() {
        let project = ProjectDisplay(identifier: first, name: "openrun", folder: "/p/openrun")
        #expect(ProjectsListRow.rows(for: ProjectsListContent(projects: [project])).map(\.name) == ["All Projects", "Needs You", "Projects", "openrun"])
        let empty = ProjectsListRow.rows(for: ProjectsListContent())
        #expect(empty.map(\.kind) == [.entry(.allSessions), .entry(.needsYou), .heading, .hint] && empty[3].name == ProjectsListRow.emptyHint)
    }

    @Test func voiceOverHearsTheCount() {
        let project = ProjectDisplay(identifier: first, name: "openrun", folder: "/p/openrun", attentionCount: 1)
        let rows = ProjectsListRow.rows(for: ProjectsListContent(projects: [project], needsYouCount: 5))
        #expect(rows.map(\.accessibilityLabel) == ["All Projects", "Needs You, 5", "Projects", "openrun, 1 needs you"])
        #expect(ProjectsListRow.rows(for: ProjectsListContent())[1].accessibilityLabel == "Needs You")
    }

    /// Rows: 0 is All Projects, 1 is Needs You, 2 is the heading, and 3 to 5 are three projects.
    @Test func aProjectMovesOnlyAmongTheProjects() {
        let down = ProjectMove(row: 3, dropRow: 6, projectCount: 3), up = ProjectMove(row: 5, dropRow: 3, projectCount: 3)
        #expect(down?.source == 0 && down?.destination == 2 && up?.source == 2 && up?.destination == 0)
        #expect(ProjectMove(row: 5, dropRow: 0, projectCount: 3)?.destinationRow == 3)
        #expect(ProjectMove(row: 3, dropRow: 9, projectCount: 3)?.destination == 2)
        #expect(ProjectMove(row: 4, dropRow: 4, projectCount: 3) == nil && ProjectMove(row: 4, dropRow: 5, projectCount: 3) == nil)
        #expect(ProjectMove(row: 2, dropRow: 4, projectCount: 3) == nil && ProjectMove(row: 6, dropRow: 3, projectCount: 3) == nil)
        #expect(ProjectMove(row: 3, dropRow: 4, projectCount: 0) == nil)
    }
}
