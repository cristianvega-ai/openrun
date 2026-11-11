import DataStorage
import Foundation
import Testing
@testable import WindowLayout

@Suite struct WindowLayoutTests {
    @Test func theLayoutKeepsEveryFactInItsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = DataFolder(path: folder.path)
        try data.create()
        let (session, project) = (UUID(), UUID())
        let layout = WindowLayout(rows: [LayoutRow(session: session)], selectedEntry: .project(project), selectedRow: session,
                                  filter: "inProgress", order: "name")
        try data.write(layout)
        #expect(try data.read(WindowLayout.self).document == layout)
        let text = try String(contentsOfFile: data.path(of: .layout), encoding: .utf8)
        #expect(text.contains("\"selectedEntry\" : \"\(project.uuidString)\""))
        #expect(text.contains("\"format\" : 1"))
    }

    @Test func aFileWithFewerKeysTakesTheFirstValues() throws {
        let layout = try JSONDecoder().decode(WindowLayout.self, from: Data("{}".utf8))
        #expect(layout == WindowLayout())
        #expect(layout.selectedEntry == .allSessions && layout.filter == "all" && layout.order == "manual")
    }

    @Test func eachEntryKeepsItsMeaningAndAnUnknownWordMeansEverySession() throws {
        let project = UUID()
        for entry in [LayoutEntry.allSessions, .needsYou, .noProject, .project(project)] {
            let data = try JSONEncoder().encode([entry])
            #expect(try JSONDecoder().decode([LayoutEntry].self, from: data) == [entry])
        }
        #expect(try JSONDecoder().decode([LayoutEntry].self, from: Data(#"["later-word"]"#.utf8)) == [.allSessions])
    }
}
