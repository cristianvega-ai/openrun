import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

/// The path with every symbolic link resolved, as the kernel reports the
/// current folder of a process. The temporary folder of macOS is behind one.
func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

extension SessionProcessIntegration {
    /// The folder, the branch and the foreground program of a session.
    @Suite struct SessionForegroundTests {
        @Test func theFolderAndTheBranchFollowTheShell() async throws {
            try await RunningSessionProcess.run { process in
                let root = canonicalPath(process.directory.path)
                let head = root + "/repository/.git/HEAD"
                try FileManager.default.createDirectory(atPath: root + "/repository/.git", withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: root + "/repository/Sources", withIntermediateDirectories: true)
                try "ref: refs/heads/main\n".write(toFile: head, atomically: true, encoding: .utf8)
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/zsh", "-f", "-i"], folder: URL(fileURLWithPath: root))
                #expect(watcher.summary(of: identifier) { $0.currentFolder == root && $0.branch == nil && $0.foregroundProgram == "zsh" } != nil)

                #expect(try process.runCommand(["send", identifier, "--enter", "cd repository/Sources"]).status == 0)
                #expect(watcher.summary(of: identifier) { $0.currentFolder == root + "/repository/Sources" && $0.branch == "main" } != nil)

                try "4f1c2a9e0b3d5c7e9f1a2b3c4d5e6f708192a3b4\n".write(toFile: head, atomically: true, encoding: .utf8)
                #expect(try process.runCommand(["send", identifier, "--enter", "cd .."]).status == 0)
                #expect(watcher.summary(of: identifier) { $0.currentFolder == root + "/repository" && $0.branch == "4f1c2a9" } != nil)
            }
        }

        /// The name of a folder can hold a mark of text direction, which a
        /// list must not obey.
        @Test func theFolderLosesTheMarksOfDirection() async throws {
            try await RunningSessionProcess.run { process in
                let root = canonicalPath(process.directory.path)
                try FileManager.default.createDirectory(atPath: root + "/gpj.\u{202E}exe", withIntermediateDirectories: true)
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/sleep", "60"], folder: URL(fileURLWithPath: root + "/gpj.\u{202E}exe"))
                #expect(watcher.summary(of: identifier) { $0.currentFolder == root + "/gpj.exe" } != nil)
            }
        }

        /// A command in line mode works also without output, and the shell
        /// at its prompt again does not.
        @Test func aSilentCommandInLineModeIsInProgress() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/zsh", "-f", "-i"])
                #expect(watcher.summary(of: identifier) { $0.foregroundProgram == "zsh" && $0.isInProgress == false } != nil)
                #expect(try process.runCommand(["send", identifier, "--enter", "sleep 30"]).status == 0)
                #expect(watcher.summary(of: identifier) { $0.foregroundProgram == "sleep" && $0.isInProgress == true } != nil)
                #expect(try process.runCommand(["send", identifier, "\u{03}"]).status == 0)
                #expect(watcher.summary(of: identifier) { $0.foregroundProgram == "zsh" && $0.isInProgress == false } != nil)
            }
        }

        /// An agent waits for keys in raw mode, so it is in progress only
        /// while it writes.
        @Test func aSilentProgramInRawModeIsNotInProgress() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; printf ready; exec sleep 60"])
                #expect(watcher.summary(of: identifier) { $0.foregroundProgram == "sleep" && $0.isInProgress == false } != nil)
                try await Task.sleep(for: .seconds(3))
                #expect(try listedSummaries(of: process).first?.isInProgress == false)
            }
        }

        @Test func outputThatStartsAndStops() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let script = "stty -icanon; sleep 2; i=0; while [ $i -lt 20 ]; do echo line $i; sleep 0.1; i=$((i+1)); done; exec sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(watcher.summary(of: identifier) { $0.isInProgress == true && $0.lastOutputAt != nil } != nil)
                let stopped = watcher.summary(of: identifier) { $0.isInProgress == false && $0.foregroundProgram == "sleep" }
                #expect(stopped?.lastOutputAt != nil)
            }
        }
    }
}
