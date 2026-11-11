import DataStorage
import Foundation
@testable import Projects
import Testing

@Suite struct ProjectStoreTests {
    static let first = Project(identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, folder: "/work/app", name: "App")
    static let second = Project(identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, folder: "/work/web", name: nil)

    @Test func saveKeepsTheFoldersApartFromTheNames() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path + "/OpenRun")
        try ProjectStore(dataFolder: folder).save(ProjectList(checked: [Self.first, Self.second]))
        let projects = try String(contentsOfFile: folder.path(of: .projects), encoding: .utf8)
        let folders = try String(contentsOfFile: folder.path(of: .projectFolders), encoding: .utf8)
        #expect(projects == """
            {
              "format" : 1,
              "projects" : [
                {
                  "identifier" : "00000000-0000-0000-0000-000000000001",
                  "name" : "App"
                },
                {
                  "identifier" : "00000000-0000-0000-0000-000000000002"
                }
              ]
            }

            """)
        #expect(folders == """
            {
              "folders" : {
                "00000000-0000-0000-0000-000000000001" : "/work/app",
                "00000000-0000-0000-0000-000000000002" : "/work/web"
              },
              "format" : 1
            }

            """)
    }

    @Test func aSavedListLoadsBack() throws {
        let temporary = try TemporaryFolder()
        let store = ProjectStore(dataFolder: DataFolder(path: temporary.path))
        let empty = try store.load()
        #expect(empty.list.projects.isEmpty)
        #expect(empty.setAsidePaths.isEmpty)
        let list = ProjectList(checked: [Self.second, Self.first])
        try store.save(list)
        let loaded = try store.load()
        #expect(loaded.list == list)
        #expect(loaded.setAsidePaths.isEmpty)
    }

    @Test func theProjectsStayWhenTheirNamesAreLost() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        let store = ProjectStore(dataFolder: folder)
        try store.save(ProjectList(checked: [Self.second, Self.first]))
        try Data("{".utf8).write(to: URL(fileURLWithPath: folder.path(of: .projects)))
        let loaded = try store.load()
        #expect(loaded.list.projects.map(\.folder) == ["/work/app", "/work/web"])
        #expect(loaded.list.projects.allSatisfy { $0.name == nil })
        #expect(loaded.setAsidePaths.count == 1)
    }
}
