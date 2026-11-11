import DataStorage
import Foundation
import SessionProcessHarness
import Testing

/// No test may read or write the data folder of the user. The harness
/// refuses to start a session process that would keep its data there.
@Suite struct UserDataGuardTests {
    @Test func theHarnessStartsNoProcessOnTheDataOfTheUser() throws {
        #expect(throws: HarnessError.self) { try RunningSessionProcess(arguments: ["--data-folder", DataFolder.defaultPath]) }
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("log")
        for arguments in [[], ["--socket", DataFolder.defaultPath + "/session.socket"], ["--socket", "x", "--data-folder", "Library/Application Support/../Application Support/OpenRun/."]] {
            #expect(throws: HarnessError.self, "\(arguments)") {
                try SocketSecurityHarness.StartedSessionProcess(arguments: arguments, folder: URL(fileURLWithPath: NSHomeDirectory()), logFile: log)
            }
        }
    }

    @Test func aProcessOfTheHarnessKeepsItsDataInItsOwnFolder() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/test")
        try UserDataGuard.check(executable: RunningSessionProcess.sessionExecutable, arguments: ["--socket", "/private/tmp/test/socket"], currentFolder: folder)
        try UserDataGuard.check(executable: RunningSessionProcess.sessionExecutable, arguments: ["--socket", "socket"], currentFolder: folder)
    }
}
