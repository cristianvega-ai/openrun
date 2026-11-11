import Foundation
import ProjectsList
import Testing
import WindowLayout
@testable import ListContent

@Suite struct RowNeighborTests {
    @Test func theRowAfterTheRemovedOneTakesTheSelectionOrElseTheRowBefore() {
        let rows = (0..<4).map { _ in UUID() }
        #expect(RowNeighbor.of(rows[1], in: rows, remaining: [rows[0], rows[2], rows[3]]) == rows[2])
        #expect(RowNeighbor.of(rows[3], in: rows, remaining: [rows[0], rows[1], rows[2]]) == rows[2])
        #expect(RowNeighbor.of(rows[1], in: rows, remaining: [rows[0]]) == rows[0])
        #expect(RowNeighbor.of(rows[1], in: rows, remaining: []) == nil)
        #expect(RowNeighbor.of(UUID(), in: rows, remaining: Set(rows)) == nil)
    }

    @Test func anEntryOfTheFirstPaneAndOfTheLayoutMapBothWays() {
        let project = UUID()
        for entry in [LayoutEntry.allSessions, .needsYou, .noProject, .project(project)] {
            #expect(ProjectsListEntry(entry).layoutEntry == entry)
        }
        #expect(ProjectsListEntry(.project(project)) == .project(project))
    }
}
