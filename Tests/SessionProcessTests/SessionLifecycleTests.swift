import Darwin
import Foundation
import PseudoTerminal
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionProcess

/// A folder with an empty zsh startup file, so that the login shell of the
/// person who runs the tests does not read their own startup files and does
/// not show the first-run questions of zsh.
private func makeCleanHome() throws -> URL {
    let home = try RunningSessionProcess.makeDirectory()
    FileManager.default.createFile(atPath: home.appendingPathComponent(".zshrc").path, contents: Data())
    return home
}

private func realPath(_ file: URL) -> String {
    String(cString: realpath(file.path, nil))
}

extension SessionProcessIntegration {
    @Suite struct SessionLifecycleTests {
        @Test func newListSendReadAndKill() async throws {
            try await RunningSessionProcess.run { process in
                let folder = try RunningSessionProcess.makeDirectory()
                defer { try? FileManager.default.removeItem(at: folder) }

                #expect(try process.listedIdentifiers().isEmpty)
                let identifier = try process.createSession(program: ["/bin/sh"], folder: folder)
                #expect(UUID(uuidString: identifier) != nil)

                let listing = try process.runCommand(["list"]).outputLines
                #expect(listing == ["\(identifier)\t\(folder.path)\t/bin/sh"])

                let send = try process.runCommand(["send", identifier, "--enter", "echo typed-$((6*7))"])
                #expect(send.status == 0)
                #expect(await process.waitForScreen(of: identifier, containing: "typed-42"))

                let kill = try process.runCommand(["kill", identifier])
                #expect(kill.status == 0)
                #expect(try process.listedIdentifiers().isEmpty)
                let afterKill = try process.runCommand(["read", identifier])
                #expect(afterKill.status == 1)
                #expect(afterKill.standardError.contains("No session"))
            }
        }

        /// The folder of a session is text that a client chose. A terminal
        /// that shows the log of the session process must not obey it.
        @Test func theLogEscapesTheFolderThatAClientChose() async throws {
            try await RunningSessionProcess.run { process in
                let parent = try RunningSessionProcess.makeDirectory()
                defer { try? FileManager.default.removeItem(at: parent) }
                let escapeCharacter = "\u{1B}"
                let folder = parent.appendingPathComponent("styled-" + escapeCharacter, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

                _ = try process.createSession(program: ["/bin/sh"], folder: folder)

                let log = process.log
                #expect(log.contains("styled-\\u{1B}"))
                #expect(!log.contains(escapeCharacter))
            }
        }

        @Test func aUniquePrefixOfTheIdentifierIsEnough() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let prefix = String(identifier.prefix(8))
                #expect(try process.runCommand(["send", prefix, "--enter", "echo by-prefix"]).status == 0)
                #expect(await process.waitForScreen(of: identifier, containing: "by-prefix"))
                // Upper case works too, because identifiers are lower case text.
                #expect(try process.runCommand(["read", prefix.uppercased()]).status == 0)
            }
        }

        @Test func aSessionRunsTheGivenFolderAndCommand() async throws {
            try await RunningSessionProcess.run { process in
                let folder = try RunningSessionProcess.makeDirectory()
                defer { try? FileManager.default.removeItem(at: folder) }
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "pwd; sleep 60"], folder: folder)
                #expect(await process.waitForScreen(of: identifier, containing: realPath(folder)))
                let listing = try process.runCommand(["list"]).outputLines
                #expect(listing == ["\(identifier)\t\(folder.path)\t/bin/sh -c pwd; sleep 60"])
            }
        }

        @Test func aSessionWithoutAFolderStartsInTheCurrentFolder() async throws {
            try await RunningSessionProcess.run { process in
                let folder = try RunningSessionProcess.makeDirectory()
                defer { try? FileManager.default.removeItem(at: folder) }
                let result = try process.runCommand(["new", "--", "/bin/sh", "-c", "pwd; sleep 60"], folder: folder)
                let identifier = try #require(result.outputLines.first)
                #expect(await process.waitForScreen(of: identifier, containing: realPath(folder)))
            }
        }

        @Test func aSessionWithoutAProgramRunsTheLoginShell() async throws {
            try await RunningSessionProcess.run { process in
                let home = try makeCleanHome()
                defer { try? FileManager.default.removeItem(at: home) }
                let identifier = try process.createSession(environment: ["HOME": home.path, "ZDOTDIR": home.path])
                // The directory service names the shell, not the code under test.
                let shell = try RunningSessionProcess.loginShellFromDirectoryService()
                let listing = try process.runCommand(["list"]).outputLines
                #expect(listing == ["\(identifier)\t\(process.directory.path)\t\(shell)"])

                // The terminal echoes what is typed, so the marker is something
                // that only a running shell can produce: the shell works out 42
                // and its own name. A login shell is called with a dash first.
                let name = "-" + (shell.split(separator: "/").last.map(String.init) ?? shell)
                _ = try process.runCommand(["send", identifier, "--enter", "echo alive-$((6*7))-\"$0\""])
                #expect(await process.waitForScreen(of: identifier, containing: "alive-42-\(name)"), "screen: \((try? process.screenText(of: identifier)) ?? "")")
            }
        }

        @Test func everyProgramGetsTheSessionEnvironment() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                // The session writes the values to a file, one per line, so that the
                // screen width and the length of the socket path cannot change what
                // the test reads.
                let file = process.directory.appendingPathComponent("session-environment")
                let script = "printf '%s\\n%s\\n%s\\n%s\\n%s\\n' \"$OPENRUN_SESSION\" \"$OPENRUN_SOCKET\" \"$TERM\" \"$COLORTERM\" \"$TERM_PROGRAM\" > '\(file.path)'"
                _ = try process.runCommand(["send", identifier, "--enter", script])
                let written = await eventually {
                    ((try? String(contentsOf: file, encoding: .utf8)) ?? "").hasSuffix("\n")
                }
                #expect(written)
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let values = text.components(separatedBy: "\n").dropLast()
                #expect(Array(values) == [identifier, process.socketPath, "xterm-256color", "truecolor", "OpenRun"])
            }
        }

        @Test func theSessionKeepsTheEnvironmentOfTheCaller() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"], environment: ["ACCOUNT_SETTING": "second-account"])
                _ = try process.runCommand(["send", identifier, "--enter", "echo setting=$ACCOUNT_SETTING"])
                #expect(await process.waitForScreen(of: identifier, containing: "setting=second-account"))
            }
        }

        @Test func aProgramThatCannotStartIsReportedToTheUser() async throws {
            try await RunningSessionProcess.run { process in
                let missingProgram = try process.runCommand(["new", "--", "/no/such/program"])
                #expect(missingProgram.status == 1)
                #expect(!missingProgram.standardError.isEmpty)
                let missingFolder = try process.runCommand(["new", "--folder", "/no/such/folder", "--", "/bin/sh"])
                #expect(missingFolder.status == 1)
                #expect(try process.listedIdentifiers().isEmpty)
            }
        }

        @Test func aProgramThatEndsLeavesTheList() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo bye; exit 5"])
                let gone = await eventually { ((try? process.listedIdentifiers()) ?? [identifier]).isEmpty }
                #expect(gone)
            }
        }

        @Test func manySessionsRunAtOnce() async throws {
            try await RunningSessionProcess.run { process in
                var identifiers: [String] = []
                for number in 0..<5 {
                    identifiers.append(try process.createSession(program: ["/bin/sh", "-c", "echo session-\(number); sleep 60"]))
                }
                #expect(Set(try process.listedIdentifiers()) == Set(identifiers))
                for (number, identifier) in identifiers.enumerated() {
                    #expect(await process.waitForScreen(of: identifier, containing: "session-\(number)"))
                }
            }
        }

        /// The harness read a crashed session process as an empty
        /// list and an empty screen, so a crash at exit passed as success.
        @Test func aDeadSessionProcessIsReportedNotReadAsEmpty() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo shown; sleep 60"])
            #expect(await process.waitForScreen(of: identifier, containing: "shown"))
            process.send(signal: SIGKILL)
            #expect(await process.waitForExit() != nil)

            #expect(throws: HarnessError.self) { try process.listedIdentifiers() }
            #expect(throws: HarnessError.self) { try process.screenText(of: identifier) }
            #expect(throws: HarnessError.self) { try process.screenText(of: identifier, includeScrollback: true) }
            // The helpers that poll treat a failure as not yet true, so a dead
            // process cannot satisfy them either.
            #expect(!(await process.waitForScreen(of: identifier, containing: "shown", timeout: .milliseconds(300))))
            #expect(!(await eventually(timeout: .milliseconds(300)) { ((try? process.listedIdentifiers()) ?? [identifier]).isEmpty }))
        }

        /// A folder name with 32 random bits could silently
        /// reuse a folder that an earlier run left behind.
        @Test func everyHarnessFolderIsNewAndEmpty() throws {
            var folders: [URL] = []
            defer { folders.forEach { try? FileManager.default.removeItem(at: $0) } }
            for _ in 0..<200 {
                let folder = try RunningSessionProcess.makeDirectory()
                folders.append(folder)
                #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
                // A leftover would show here, because nothing was put in it yet.
                FileManager.default.createFile(atPath: folder.appendingPathComponent("mark").path, contents: Data())
            }
            #expect(Set(folders.map(\.path)).count == folders.count)
            let mode = try FileManager.default.attributesOfItem(atPath: folders[0].path)[.posixPermissions] as? Int
            #expect(mode == 0o700)
        }

        @Test func aMissingSessionProcessIsReportedClearly() throws {
            let directory = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let socket = directory.appendingPathComponent("absent").path
            let result = try RunningSessionProcess.runOpenrun(["list", "--socket", socket], in: directory)
            #expect(result.status == 1)
            #expect(result.standardError.contains("No session process"))
            #expect(result.standardOutput.isEmpty)
        }
    }
}
