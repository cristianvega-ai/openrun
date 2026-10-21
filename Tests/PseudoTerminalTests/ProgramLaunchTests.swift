import Darwin
import Foundation
import Testing

@testable import PseudoTerminal

/// The folder a program is launched in, with the files a test needs. The
/// session process runs somewhere else, so a lookup against its own folder
/// would find the wrong files.
private func makeLaunchFolder() throws -> URL {
    // The test target has no access to the harness, so it repeats the harness
    // rule: a long TMPDIR gives way to the temporary folder of the user.
    var base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    if base.utf8.count > 76 {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 { base = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    }
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

/// A launch of a program that ends at once, with the given values.
private func trueProgram(
    executablePath: String = "/usr/bin/true",
    argumentZero: String? = nil,
    arguments: [String] = [],
    folder: String = "/",
    environment: [String: String] = [:]
) -> ProgramLaunch {
    ProgramLaunch(
        executablePath: executablePath,
        argumentZero: argumentZero,
        arguments: arguments,
        folder: folder,
        environment: environment.merging(["PATH": "/usr/bin:/bin"]) { given, _ in given },
        size: PseudoTerminalSize(columns: 80, rows: 24)
    )
}

/// Launches the program and returns the error of the launch, or `nil` when
/// the program started. A program that started is ended at once.
private func launchError(_ launching: ProgramLaunch) async -> PseudoTerminalError? {
    do {
        let terminal = try PseudoTerminal(launching: launching)
        await terminal.terminate()
        return nil
    } catch {
        return error as? PseudoTerminalError
    }
}

@Suite struct ProgramLaunchTests {
    /// A name with "=" made a second entry for a name that
    /// OpenRun sets, and a NUL cut a name or a value short without a word.
    @Test(arguments: [
        (["": "value"], "an environment variable has an empty name"),
        (["OPENRUN_SOCKET=/tmp/elsewhere": "value"], "an environment variable name holds an equals sign (=)"),
        (["NAME\u{0}HIDDEN": "value"], "an environment variable name holds a NUL character"),
        (["NAME": "value\u{0}hidden"], "the value of an environment variable holds a NUL character"),
    ])
    func anEnvironmentThatWouldReachTheProgramChangedIsRefused(environment: [String: String], problem: String) async {
        let error = await launchError(trueProgram(environment: environment))
        #expect(error?.description == "The program was not started: \(problem).")
    }

    /// A NUL ended the C string of a value, so the program
    /// ran with a shorter argument, another program name, or another folder.
    @Test(arguments: [
        (trueProgram(executablePath: "/usr/bin/true\u{0}/hidden"), "the program name holds a NUL character"),
        (trueProgram(argumentZero: "true\u{0}hidden"), "the name the program sees for itself holds a NUL character"),
        (trueProgram(arguments: ["first", "sec\u{0}ond"]), "argument 2 holds a NUL character"),
        (trueProgram(folder: "/tmp\u{0}/hidden"), "the folder holds a NUL character"),
    ])
    func aNullCharacterInALaunchValueIsRefused(launching: ProgramLaunch, problem: String) async {
        let error = await launchError(launching)
        #expect(error?.description == "The program was not started: \(problem).")
    }

    /// Only names are split at "=", so a value may hold one.
    @Test func aValueWithAnEqualsSignReachesTheProgramWhole() async throws {
        var launching = trueProgram(executablePath: "/usr/bin/env", environment: ["EQUATION": "one=two"])
        launching.environment = ["EQUATION": "one=two"]
        let terminal = try PseudoTerminal(launching: launching)
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        let printed = String(decoding: collected, as: UTF8.self).split(whereSeparator: \.isNewline)
        #expect(printed == ["EQUATION=one=two"])
    }

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

    @Test func aRelativePathEntryProgramReallyRunsAfterTheFolderChange() async throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appendingPathComponent("tools/tool")
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho ran-from-launch-folder\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let terminal = try PseudoTerminal(launching: launch("tool", searchPath: "tools", folder: folder))
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        #expect(String(decoding: collected, as: UTF8.self).contains("ran-from-launch-folder"))
        #expect(await terminal.waitForExit() == .exited(status: 0))
    }

    @Test func anExecutableWithoutAShebangRunsThroughTheShell() async throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("plain-script")
        try Data("echo plain-$0-$1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        var launching = launch("./plain-script", searchPath: "/usr/bin:/bin", folder: folder)
        launching.arguments = ["argument"]
        let terminal = try PseudoTerminal(launching: launching)
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        #expect(String(decoding: collected, as: UTF8.self).contains("plain-./plain-script-argument"))
        #expect(await terminal.waitForExit() == .exited(status: 0))
    }

    @Test func aMissingFolderIsNamedAsTheFolderEvenWithARelativePath() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-" + UUID().uuidString)
        #expect(throws: PseudoTerminalError.systemCallFailed(function: "chdir", code: ENOENT)) {
            _ = try PseudoTerminal(launching: launch("tool", searchPath: "tools", folder: missing))
        }
        #expect(throws: PseudoTerminalError.systemCallFailed(function: "chdir", code: ENOENT)) {
            _ = try PseudoTerminal(launching: launch("tool", searchPath: nil, folder: missing))
        }
    }

    @Test func aFolderThatIsAFileIsNamedAsNotAFolder() throws {
        let folder = try makeLaunchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("file")
        try Data().write(to: file)
        #expect(throws: PseudoTerminalError.systemCallFailed(function: "chdir", code: ENOTDIR)) {
            _ = try PseudoTerminal(launching: launch("tool", searchPath: "tools", folder: file))
        }
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
