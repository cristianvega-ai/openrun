import Darwin
import Foundation
import PseudoTerminal
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionProcess


extension SessionProcessIntegration {
    @Suite struct SessionLifecycleTests {

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
    }
}
