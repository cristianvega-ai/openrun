import Foundation
@testable import Projects
import Testing

@Suite struct ProjectListAddTests {
    let temporary: TemporaryFolder
    /// The temporary folder with its symbolic links resolved.
    let real: String

    init() throws {
        temporary = try TemporaryFolder()
        for name in ["app", "application"] {
            try FileManager.default.createDirectory(atPath: temporary.path + "/" + name, withIntermediateDirectories: false)
        }
        real = try #require(realpath(temporary.path, nil).map { String(cString: $0) })
    }

    @Test func addPutsTheResolvedFolderAtTheEnd() throws {
        var list = ProjectList()
        let first = try list.add(folder: temporary.path + "/app/")
        let second = try list.add(folder: "application", name: "  Main  ", currentFolder: temporary.path)
        #expect(list.projects == [first, second])
        #expect(first.folder == real + "/app")
        #expect(first.name == nil)
        #expect(first.shownName == "app")
        #expect(second.name == "Main")
        #expect(second.shownName == "Main")
        #expect(first.identifier != second.identifier)
    }

    @Test func addRefusesASecondSpellingOfAFolder() throws {
        var list = ProjectList()
        let first = try list.add(folder: temporary.path + "/app")
        #expect(throws: ProjectListError.duplicateFolder(path: real + "/app", project: first.identifier)) {
            try list.add(folder: real + "/application/../app/")
        }
        #expect(list.projects == [first])
    }

    @Test func addRefusesABadNameAndChangesNothing() throws {
        var list = ProjectList()
        for name in [String(repeating: "x", count: 101), "one\ntwo", "bell\u{7}", "c1\u{9B}", "app\u{202E}gnp.exe", "a\u{2028}b"] {
            #expect(throws: ProjectListError.invalidName) { try list.add(folder: temporary.path + "/app", name: name) }
        }
        #expect(list.projects.isEmpty)
        #expect(try list.add(folder: temporary.path + "/app", name: " \n ").name == nil)
    }

    @Test func addRefusesWhenTheListIsFull() throws {
        let projects = (0..<ProjectList.countLimit).map { Project(identifier: UUID(), folder: "/folder/\($0)", name: nil) }
        var list = ProjectList(checked: projects)
        #expect(throws: ProjectListError.tooManyProjects(limit: 1000)) { try list.add(folder: temporary.path + "/app") }
    }

    @Test func removeTakesOutOneProject() throws {
        var list = ProjectList()
        let first = try list.add(folder: temporary.path + "/app")
        let second = try list.add(folder: temporary.path + "/application")
        try list.remove(identifier: first.identifier)
        #expect(list.projects == [second])
        let unknown = UUID()
        #expect(throws: ProjectListError.unknownProject(unknown)) { try list.remove(identifier: unknown) }
        #expect(list.project(identifier: second.identifier) == second)
        #expect(list.project(identifier: first.identifier) == nil)
    }

    /// A project without a folder counts toward the limit, so a client
    /// must be able to see it and remove it.
    @Test func removeTakesOutAProjectWithoutAFolder() throws {
        let hidden = ProjectWithoutFolder(identifier: UUID(), name: "Elsewhere")
        let projects = (1..<ProjectList.countLimit).map { Project(identifier: UUID(), folder: "/folder/\($0)", name: nil) }
        var list = ProjectList(checked: projects, projectsWithoutFolder: [hidden])
        #expect(list.projectsWithoutFolder == [hidden])
        #expect(throws: ProjectListError.tooManyProjects(limit: 1000)) { try list.add(folder: temporary.path + "/app") }
        try list.remove(identifier: hidden.identifier)
        #expect(list.projectsWithoutFolder.isEmpty)
        #expect(list.projects == projects)
        try list.add(folder: temporary.path + "/app")
        #expect(throws: ProjectListError.unknownProject(hidden.identifier)) { try list.remove(identifier: hidden.identifier) }
    }
}
