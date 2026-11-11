import Foundation
import SessionProtocol
import Testing
@testable import CommandLineTool

@Suite struct ProjectMatchTests {
    private static let app = ProjectSummary(identifier: UUID(uuidString: "3F2A9C1E-0000-4000-8000-000000000001")!, name: nil, folder: "/work/app")
    private static let tool = ProjectSummary(identifier: UUID(uuidString: "3F2B0000-0000-4000-8000-000000000002")!, name: nil, folder: "/work/tool")
    private static let gone = ProjectSummary(identifier: UUID(uuidString: "77000000-0000-4000-8000-000000000003")!, name: "Old", folder: nil)
    private static let projects = [app, tool, gone]

    private static func find(_ typed: String) throws -> ProjectSummary {
        try ProjectMatch.find(typed, in: projects, currentFolder: "/work", homeFolder: "/Users/someone")
    }

    @Test func aUniqueStartOfAnIdentifierFindsTheProject() throws {
        #expect(try Self.find("3F2A") == Self.app)
        #expect(try Self.find("77") == Self.gone)
        #expect(try Self.find(Self.tool.identifierText) == Self.tool)
    }

    /// A folder that does not exist on this Mac keeps the spelling of the
    /// session process, so the project of a deleted folder can be removed.
    @Test func aFolderFindsTheProjectAlsoWhenItIsGone() throws {
        #expect(try Self.find("/work/app/") == Self.app)
        #expect(try Self.find("tool") == Self.tool)
        #expect(try Self.find("./app/../tool") == Self.tool)
        let home = try ProjectMatch.find("~/app", in: [ProjectSummary(identifier: UUID(), name: nil, folder: "/Users/someone/app")],
                                         currentFolder: "/", homeFolder: "/Users/someone")
        #expect(home.folder == "/Users/someone/app")
    }

    @Test func aStartOfTwoIdentifiersListsThemAndNothingMatchesFails() throws {
        #expect(throws: CommandLineToolError.self) { try Self.find("3f2") }
        do {
            _ = try Self.find("3f2")
        } catch CommandLineToolError.failureWithList(_, let lines) {
            #expect(lines == ["  \(Self.app.identifierText)  /work/app", "  \(Self.tool.identifierText)  /work/tool"])
        }
        #expect(throws: CommandLineToolError.self) { try Self.find("nothing") }
    }
}
