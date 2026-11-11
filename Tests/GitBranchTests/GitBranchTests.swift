import Foundation
import Testing
@testable import GitBranch

/// Each test builds the files of a repository by hand in a new folder, so
/// no `git` program and no repository of the user takes part.
@Suite final class GitBranchTests {
    private let root: String

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("git-branch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // The temporary folder of macOS is behind a symbolic link.
        root = base.resolvingSymlinksInPath().path
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ text: String, to relativePath: String) throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeFolder(_ relativePath: String) throws -> String {
        let path = root + "/" + relativePath
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test func aFolderDeepInARepositoryHasTheBranchOfItsHead() throws {
        try write("ref: refs/heads/feature/lists\n", to: "work/.git/HEAD")
        #expect(GitBranch.name(forFolder: try makeFolder("work/Sources/Deep")) == "feature/lists")
        #expect(GitBranch.name(forFolder: root + "/work/") == "feature/lists")
    }

    @Test func aDetachedHeadShowsTheStartOfTheCommit() throws {
        try write("4f1c2a9e0b3d5c7e9f1a2b3c4d5e6f708192a3b4\n", to: "work/.git/HEAD")
        #expect(GitBranch.name(forFolder: root + "/work") == "4f1c2a9")
    }

    @Test func aFolderOutsideEveryRepositoryHasNoBranch() throws {
        #expect(GitBranch.name(forFolder: try makeFolder("plain/inside")) == nil)
        #expect(GitBranch.name(forFolder: "relative/path") == nil)
    }

    /// A worktree and a submodule have a `.git` file that names the folder
    /// of the repository, with an absolute or a relative path.
    @Test func aGitFileLeadsToTheFolderThatItNames() throws {
        try write("ref: refs/heads/main\n", to: "main/.git/HEAD")
        try write("ref: refs/heads/topic\n", to: "main/.git/worktrees/topic/HEAD")
        try write("gitdir: \(root)/main/.git/worktrees/topic\n", to: "topic/.git")
        #expect(GitBranch.name(forFolder: try makeFolder("topic/Sources")) == "topic")
        try write("ref: refs/heads/vendor\n", to: "main/.git/modules/library/HEAD")
        try write("gitdir: ../.git/modules/library\n", to: "main/library/.git")
        #expect(GitBranch.name(forFolder: root + "/main/library") == "vendor")
    }

    /// The nearest `.git` decides, as for git itself. A broken one gives no
    /// branch, and the search does not go on to a repository above it.
    @Test func aFileThatCannotBeReadGivesNoBranch() throws {
        try write("ref: refs/heads/outer\n", to: "outer/.git/HEAD")
        try write("not a git file\n", to: "outer/inner/.git")
        #expect(GitBranch.name(forFolder: root + "/outer/inner") == nil)
        try write("gitdir: \(root)/missing\n", to: "outer/second/.git")
        #expect(GitBranch.name(forFolder: root + "/outer/second") == nil)
        try write("not a reference\n", to: "outer/.git/HEAD")
        #expect(GitBranch.name(forFolder: root + "/outer") == nil)
    }

    @Test func aHeadLargerThanTheLimitIsNotRead() throws {
        try write("ref: refs/heads/" + String(repeating: "a", count: GitBranch.readLimit), to: "large/.git/HEAD")
        #expect(GitBranch.name(forFolder: root + "/large") == nil)
        #expect(mkfifo(root + "/pipe", 0o600) == 0)
        #expect(GitBranch.firstLine(ofFile: root + "/pipe") == nil)
    }
}
