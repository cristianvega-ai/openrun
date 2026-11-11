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

    @Test func aRelativePathHasNoStandardSpelling() {
        #expect(ProjectFolderPath.standardized("work/app") == nil)
        #expect(ProjectFolderPath.standardized("") == nil)
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

    @Test func resolveStartsTheHomeAndRelativePaths() throws {
        let temporary = try TemporaryFolder()
        try FileManager.default.createDirectory(atPath: temporary.path + "/work", withIntermediateDirectories: false)
        let real = try #require(realpath(temporary.path, nil).map { String(cString: $0) })
        #expect(try ProjectFolderPath.resolve("~", homeFolder: temporary.path, currentFolder: nil) == real)
        #expect(try ProjectFolderPath.resolve("~/work/", homeFolder: temporary.path, currentFolder: nil) == real + "/work")
        #expect(try ProjectFolderPath.resolve("work", homeFolder: "/", currentFolder: temporary.path) == real + "/work")
        #expect(try ProjectFolderPath.resolve("./work/..", homeFolder: "/", currentFolder: temporary.path) == real)
    }

    @Test func resolveFollowsSymbolicLinks() throws {
        let temporary = try TemporaryFolder()
        try FileManager.default.createDirectory(atPath: temporary.path + "/work", withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: temporary.path + "/link", withDestinationPath: "work")
        let resolved = try ProjectFolderPath.resolve(temporary.path + "/link", homeFolder: "/", currentFolder: nil)
        #expect(resolved.hasPrefix("/private/"))
        #expect(resolved.hasSuffix("/work"))
    }

    @Test func resolveRefusesWhatIsNotAFolder() throws {
        let temporary = try TemporaryFolder()
        let file = temporary.path + "/file"
        try Data().write(to: URL(fileURLWithPath: file))
        #expect(throws: ProjectListError.relativeFolder(path: "work")) {
            try ProjectFolderPath.resolve("work", homeFolder: "/", currentFolder: nil)
        }
        #expect(throws: ProjectListError.folderDoesNotExist(path: temporary.path + "/missing")) {
            try ProjectFolderPath.resolve(temporary.path + "/missing/", homeFolder: "/", currentFolder: nil)
        }
        let realFile = try #require(realpath(file, nil).map { String(cString: $0) })
        #expect(throws: ProjectListError.notAFolder(path: realFile)) {
            try ProjectFolderPath.resolve(file, homeFolder: "/", currentFolder: nil)
        }
    }
}
