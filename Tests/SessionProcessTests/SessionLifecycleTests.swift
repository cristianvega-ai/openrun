import Darwin
import Foundation
import PseudoTerminal
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionProcess


private func realPath(_ file: URL) -> String {
    String(cString: realpath(file.path, nil))
}

extension SessionProcessIntegration {
    @Suite struct SessionLifecycleTests {

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
