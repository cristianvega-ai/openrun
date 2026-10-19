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
