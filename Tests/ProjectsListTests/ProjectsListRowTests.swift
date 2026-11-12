import Foundation
import Testing
@testable import ProjectsList

@Suite struct ProjectsListRowTests {
    private let first = UUID(), second = UUID()

    @Test func theFixedEntriesComeFirstAndNoProjectLast() {
        let content = ProjectsListContent(
            projects: [ProjectDisplay(identifier: first, name: "openrun", folder: "/p/openrun", attentionCount: 2),
                       ProjectDisplay(identifier: second, name: "website", folder: "/p/website")],
            needsYouCount: 3, noProjectAttentionCount: 1)
        let rows = ProjectsListRow.rows(for: content)
        #expect(rows.map(\.entry) == [.allSessions, .needsYou, .project(first), .project(second), .noProject])
        #expect(rows.map(\.name) == ["All Projects", "Needs You", "openrun", "website", "Other Folders"])
        #expect(rows.map(\.attentionCount) == [0, 3, 2, 0, 1])
        #expect(rows[2].help == "/p/openrun" && rows[2].projectIdentifier == first && rows[1].projectIdentifier == nil)
        #expect(ProjectsListRow.firstProjectRow == 2)
    }

    @Test func otherFoldersShowsOnlyWhenWorkIsOutsideEveryProject() {
        let project = ProjectDisplay(identifier: first, name: "openrun", folder: "/p/openrun")
        #expect(ProjectsListRow.rows(for: ProjectsListContent(projects: [project])).map(\.name) == ["All Projects", "Needs You", "openrun"])
        let outside = ProjectsListRow.rows(for: ProjectsListContent(projects: [project], showsOtherFolders: true))
        #expect(outside.last?.entry == .noProject && outside.last?.name == "Other Folders")
    }

    @Test func voiceOverHearsTheCount() {
        let project = ProjectDisplay(identifier: first, name: "openrun", folder: "/p/openrun", attentionCount: 1)
        let rows = ProjectsListRow.rows(for: ProjectsListContent(projects: [project], needsYouCount: 5, noProjectAttentionCount: 4))
        #expect(rows.map(\.accessibilityLabel) == ["All Projects", "Needs You, 5", "openrun, 1 needs you", "Other Folders, 4 need you"])
        #expect(ProjectsListRow.rows(for: ProjectsListContent())[1].accessibilityLabel == "Needs You")
    }

    /// Rows: 0 is All Sessions, 1 is Needs You, 2 to 4 are three projects, 5 is No Project.
    @Test func aProjectMovesOnlyAmongTheProjects() {
        let down = ProjectMove(row: 2, dropRow: 5, projectCount: 3), up = ProjectMove(row: 4, dropRow: 2, projectCount: 3)
        #expect(down?.source == 0 && down?.destination == 2 && up?.source == 2 && up?.destination == 0)
        #expect(ProjectMove(row: 4, dropRow: 0, projectCount: 3)?.destinationRow == 2)
        #expect(ProjectMove(row: 2, dropRow: 9, projectCount: 3)?.destination == 2)
        #expect(ProjectMove(row: 3, dropRow: 3, projectCount: 3) == nil && ProjectMove(row: 3, dropRow: 4, projectCount: 3) == nil)
        #expect(ProjectMove(row: 1, dropRow: 3, projectCount: 3) == nil && ProjectMove(row: 5, dropRow: 2, projectCount: 3) == nil)
        #expect(ProjectMove(row: 2, dropRow: 3, projectCount: 0) == nil)
    }
}
