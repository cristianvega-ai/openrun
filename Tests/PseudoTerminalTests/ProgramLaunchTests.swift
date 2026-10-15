import Darwin
import Foundation
import Testing

@testable import PseudoTerminal

/// The folder a program is launched in, with the files a test needs. The
/// session process runs somewhere else, so a lookup against its own folder
/// would find the wrong files.
private func makeLaunchFolder() throws -> URL {
    let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    let folder = URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("launch-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func makeFile(_ path: URL, executable: Bool) throws {
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: path.path)
}

private func launch(_ name: String, searchPath: String?, folder: URL) -> ProgramLaunch {
    var environment: [String: String] = [:]
    if let searchPath { environment["PATH"] = searchPath }
    return ProgramLaunch(
        executablePath: name,
        folder: folder.path,
        environment: environment,
        size: PseudoTerminalSize(columns: 80, rows: 24)
    )
}


@Suite struct ProgramLaunchTests {

    @Test func aRelativePathEntryIsSearchedInTheLaunchFolder() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeFile(folder.appendingPathComponent("tools/tool"), executable: true)

        let resolved = try launch("tool", searchPath: "tools", folder: folder).resolvedExecutablePath()
        // execve runs after chdir, so the path is checked against the folder
        // and then stays relative to it.
        #expect(resolved == "tools/tool")
    }

    @Test(arguments: [".", ""])
    func aDotOrEmptyPathEntryMeansTheLaunchFolder(entry: String) throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeFile(folder.appendingPathComponent("tool"), executable: true)

        let resolved = try launch("tool", searchPath: entry, folder: folder).resolvedExecutablePath()
        #expect(resolved == "./tool")
    }

    @Test func anEmptyEntryInTheMiddleOfThePathIsNotSkipped() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeFile(folder.appendingPathComponent("tool"), executable: true)

        let resolved = try launch("tool", searchPath: "/nonexistent-one::/nonexistent-two", folder: folder).resolvedExecutablePath()
        #expect(resolved == "./tool")
    }

    @Test func aDirectoryWithTheProgramNameIsSkipped() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("first/tool"), withIntermediateDirectories: true)
        try makeFile(folder.appendingPathComponent("second/tool"), executable: true)

        let resolved = try launch("tool", searchPath: "first:second", folder: folder).resolvedExecutablePath()
        #expect(resolved == "second/tool")
    }

    @Test func aDirectoryOnAnAbsolutePathEntryIsSkipped() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("first/tool"), withIntermediateDirectories: true)
        try makeFile(folder.appendingPathComponent("second/tool"), executable: true)

        let searchPath = "\(folder.path)/first:\(folder.path)/second"
        let resolved = try launch("tool", searchPath: searchPath, folder: folder).resolvedExecutablePath()
        #expect(resolved == "\(folder.path)/second/tool")
    }

    @Test func aFileWithoutTheExecutePermissionIsSkipped() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeFile(folder.appendingPathComponent("first/tool"), executable: false)
        try makeFile(folder.appendingPathComponent("second/tool"), executable: true)

        let resolved = try launch("tool", searchPath: "first:second", folder: folder).resolvedExecutablePath()
        #expect(resolved == "second/tool")
    }

    @Test func aProgramThatIsNowhereOnThePathIsNotFound() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: PseudoTerminalError.programNotFound(name: "tool")) {
            try launch("tool", searchPath: "first:/nonexistent", folder: folder).resolvedExecutablePath()
        }
    }

    @Test func aLaunchWithoutPathUsesTheSystemDefault() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try launch("sh", searchPath: nil, folder: folder).resolvedExecutablePath().hasSuffix("/sh"))
    }

    @Test func aNameWithASlashIsUsedAsGiven() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try launch("./tool", searchPath: "/usr/bin", folder: folder).resolvedExecutablePath() == "./tool")
    }

    @Test func reapingRetriesAfterAnInterruption() {
        var calls = 0
        let reaped = ProgramLaunch.reap(processIdentifier: 4242) { identifier, _, _ in
            calls += 1
            if calls <= 2 {
                errno = EINTR
                return -1
            }
            return identifier
        }
        #expect(reaped)
        #expect(calls == 3)
    }

    @Test func reapingStopsOnAnErrorThatIsNotAnInterruption() {
        var calls = 0
        let reaped = ProgramLaunch.reap(processIdentifier: 4242) { _, _, _ in
            calls += 1
            errno = ECHILD
            return -1
        }
        #expect(!reaped)
        #expect(calls == 1)
    }
}
