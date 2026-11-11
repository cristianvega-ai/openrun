import Foundation
@testable import Projects
import Testing

@Suite struct ProjectListOrderTests {
    static let projects = ["a", "b", "c", "d"].map { Project(identifier: UUID(), folder: "/work/" + $0, name: nil) }

    static func names(_ list: ProjectList) -> String {
        list.projects.map(\.shownName).joined()
    }

    @Test(arguments: [(0, 0, "abcd"), (0, 3, "bcda"), (3, 0, "dabc"), (1, 2, "acbd"), (2, 1, "acbd")])
    func moveGivesTheProjectItsNewPlace(from: Int, to place: Int, expected: String) throws {
        var list = ProjectList(checked: Self.projects)
        try list.move(identifier: Self.projects[from].identifier, to: place)
        #expect(Self.names(list) == expected)
    }

    @Test func moveRefusesAPlaceOutsideTheList() throws {
        var list = ProjectList(checked: Self.projects)
        for place in [-1, 4] {
            #expect(throws: ProjectListError.placeOutOfRange(place: place, count: 4)) {
                try list.move(identifier: Self.projects[0].identifier, to: place)
            }
        }
        let unknown = UUID()
        #expect(throws: ProjectListError.unknownProject(unknown)) { try list.move(identifier: unknown, to: 0) }
        #expect(Self.names(list) == "abcd")
    }

    @Test func renameGivesAndTakesAwayAName() throws {
        var list = ProjectList(checked: Self.projects)
        let identifier = Self.projects[1].identifier
        try list.rename(identifier: identifier, to: " Second ")
        #expect(list.project(identifier: identifier)?.shownName == "Second")
        #expect(throws: ProjectListError.invalidName) { try list.rename(identifier: identifier, to: "\u{1B}[2J") }
        #expect(list.project(identifier: identifier)?.name == "Second")
        try list.rename(identifier: identifier, to: "")
        #expect(list.project(identifier: identifier)?.shownName == "b")
        let unknown = UUID()
        #expect(throws: ProjectListError.unknownProject(unknown)) { try list.rename(identifier: unknown, to: "x") }
    }

    @Test func theRootShowsAsASlash() {
        #expect(Project(identifier: UUID(), folder: "/", name: nil).shownName == "/")
    }
}
