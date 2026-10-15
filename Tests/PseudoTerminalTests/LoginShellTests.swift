import Darwin
import Foundation
import Testing
@testable import PseudoTerminal

/// The shell that the directory service names for the current user, asked of
/// `dscl`. It is the oracle for `LoginShell.current()`, which must not be its
/// own oracle.
private func shellFromDirectoryService() throws -> String {
    let reader = Process()
    reader.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
    reader.arguments = [".", "-read", "/Users/" + NSUserName(), "UserShell"]
    let pipe = Pipe()
    reader.standardOutput = pipe
    reader.standardError = FileHandle.nullDevice
    try reader.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    reader.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    try #require(reader.terminationStatus == 0 && text.hasPrefix("UserShell:"), "dscl said: \(text)")
    return text.dropFirst("UserShell:".count).trimmingCharacters(in: .whitespaces)
}

@Suite struct LoginShellTests {
    @Test func theCurrentShellIsAnExecutableFile() {
        let shell = LoginShell.current()
        #expect(access(shell.path, X_OK) == 0)
    }

    @Test func theCurrentShellIsTheOneThatTheDirectoryServiceNamesForTheUser() throws {
        #expect(LoginShell.current().path == (try shellFromDirectoryService()))
    }

    @Test func aLoginShellNameStartsWithADash() {
        #expect(LoginShell(path: "/bin/zsh").argumentZero == "-zsh")
        #expect(LoginShell(path: "/opt/homebrew/bin/fish").argumentZero == "-fish")
    }

    @Test func theLoginShellRunsAsALoginShell() async throws {
        // Running the shell in a clean environment keeps the user's profile
        // out of the test. Only the dash in the name matters here.
        let launch = LoginShell(path: "/bin/sh").launch(
            folder: "/",
            environment: ["PATH": "/usr/bin:/bin"],
            size: PseudoTerminalSize(columns: 80, rows: 24)
        )
        let terminal = try PseudoTerminal(launching: launch)
        terminal.write(Array("echo $0; exit\n".utf8))
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        #expect(lines(String(decoding: collected, as: UTF8.self)).contains("-sh"))
    }
}
