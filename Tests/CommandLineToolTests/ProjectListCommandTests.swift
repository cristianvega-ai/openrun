import Foundation
import SessionProtocol
import Testing
@testable import CommandLineTool

@Suite struct ProjectListCommandTests {
    private static let first = UUID(uuidString: "3F2A9C1E-0000-4000-8000-000000000001")!
    private static let second = UUID(uuidString: "3F2A9C1E-0000-4000-8000-000000000002")!

    /// A name or a folder cannot forge a column or a line, or drive the
    /// terminal. A project without a folder shows its name and no folder.
    @Test func eachProjectIsOneLineOfThreeEscapedColumns() {
        let projects = [
            ProjectSummary(identifier: Self.first, name: nil, folder: "/work/app\u{1B}[31m\tx\ny\\"),
            ProjectSummary(identifier: Self.second, name: "Old", folder: nil),
        ]
        #expect(ProjectListCommand.lines(of: projects) == """
            3f2a9c1e-0000-4000-8000-000000000001\tapp\\u{1B}[31m\\tx\\ny\\\\\t/work/app\\u{1B}[31m\\tx\\ny\\\\
            3f2a9c1e-0000-4000-8000-000000000002\tOld\t

            """)
        #expect(ProjectListCommand.shownName(of: ProjectSummary(identifier: Self.first, name: nil, folder: "/")) == "/")
    }

    @Test func theJSONHasEveryKeyOfEachProject() throws {
        let document = try ProjectListCommand.document(of: [ProjectSummary(identifier: Self.second, name: nil, folder: "/work/app")])
        let object = try #require(JSONSerialization.jsonObject(with: Data(document.utf8)) as? [String: [[String: Any]]])
        let project = try #require(object["projects"]?.first)
        #expect(Set(project.keys) == ["identifier", "name", "folder"])
        #expect(project["identifier"] as? String == "3f2a9c1e-0000-4000-8000-000000000002")
        #expect(project["name"] is NSNull && project["folder"] as? String == "/work/app")
    }
}
