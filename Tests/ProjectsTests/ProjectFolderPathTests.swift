import Foundation
@testable import Projects
import Testing

@Suite struct ProjectFolderPathTests {
    @Test(arguments: [
        ("/work/app/", "/work/app"),
        ("/work//app/./", "/work/app"),
        ("/work/app/../other", "/work/other"),
        ("/..", "/"),
        ("/", "/"),
        ("//", "/"),
    ])
    func aPathHasOneStandardSpelling(path: String, expected: String) {
        #expect(ProjectFolderPath.standardized(path) == expected)
    }

    @Test func aFolderHoldsAnotherOnlyByWholeNames() {
        func holds(_ folder: String, _ other: String) -> Bool {
            ProjectFolderPath.holds(ProjectFolderPath.components(of: folder), ProjectFolderPath.components(of: other))
        }
        #expect(holds("/work/app", "/work/app"))
        #expect(holds("/work/app", "/work/app/Sources"))
        #expect(!holds("/work/app", "/work/application"))
        #expect(!holds("/work/app/Sources", "/work/app"))
        #expect(holds("/", "/work"))
    }
}
