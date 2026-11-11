import Foundation
@testable import Projects
import Testing

@Suite struct ProjectHoldingTests {
    static func list(_ folders: [String]) -> ProjectList {
        ProjectList(checked: folders.map { Project(identifier: UUID(), folder: $0, name: nil) })
    }

    static func holder(of folder: String, in list: ProjectList) -> String? {
        list.project(holding: folder)?.folder
    }

    @Test(arguments: [
        ("/work/app", "/work/app"),
        ("/work/app/", "/work/app"),
        ("/work/app/Sources/Feature", "/work/app"),
        ("/work/app/packages/core", "/work/app/packages/core"),
        ("/work/app/packages/core/../web", "/work/app"),
        ("/work/app/packages/../../app/packages/core/lib", "/work/app/packages/core"),
        ("/work/application", "/work"),
        ("/work", "/work"),
        ("//work//app//", "/work/app"),
    ])
    func theDeepestHolderWins(folder: String, expected: String) {
        let list = Self.list(["/work/app/packages/core", "/work", "/work/app"])
        #expect(Self.holder(of: folder, in: list) == expected)
    }

    @Test func aFolderOutsideEveryProjectHasNone() {
        let list = Self.list(["/work/app"])
        #expect(Self.holder(of: "/work/application", in: list) == nil)
        #expect(Self.holder(of: "/work", in: list) == nil)
        #expect(Self.holder(of: "/", in: list) == nil)
        #expect(Self.holder(of: "work/app", in: list) == nil)
        #expect(Self.holder(of: "", in: list) == nil)
    }

    @Test func theRootHoldsEveryFolder() {
        let list = Self.list(["/", "/work/app"])
        #expect(Self.holder(of: "/", in: list) == "/")
        #expect(Self.holder(of: "/Users/someone", in: list) == "/")
        #expect(Self.holder(of: "/work/app/x", in: list) == "/work/app")
        #expect(Self.holder(of: "/..", in: list) == "/")
    }

    @Test func anEmptyListHoldsNothing() {
        #expect(ProjectList().project(holding: "/work") == nil)
    }
}
