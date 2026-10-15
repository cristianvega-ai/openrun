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
}
