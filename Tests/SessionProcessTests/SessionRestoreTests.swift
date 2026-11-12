import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing

/// The sessions that come back after a restart of the session process,
/// such as after a restart of the Mac (decision of 2026-10-15).
@Suite struct SessionRestoreTests {
    @Test func aSessionComesBackAsAShellInItsFolderWithItsIdentifierAndItsName() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = folder.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let first = try RunningSessionProcess(directory: folder)
        let kept = try first.createSession(program: ["/bin/cat"], folder: work)
        let gone = try first.createSession(program: ["/bin/cat"], folder: folder.appendingPathComponent("work"))
        let client = try SessionClient(location: SocketLocation(path: first.socketPath))
        try client.rename(session: try #require(UUID(uuidString: kept)), to: "Build")
        let file = folder.appendingPathComponent("sessions.json")
        #expect(await eventually { (try? String(contentsOf: file, encoding: .utf8))?.contains("\"name\" : \"Build\"") == true })
        // The folder of the second session goes away while the session process does not run.
        first.stop()
        #expect(try String(contentsOf: file, encoding: .utf8).lowercased().contains(gone))
        try FileManager.default.removeItem(at: work)

        let second = try RunningSessionProcess(directory: folder, logName: "log2")
        defer { second.stop() }
        let sessions = try SessionClient(location: SocketLocation(path: second.socketPath)).summaries()
        #expect(Set(sessions.map(\.identifierText)) == [kept, gone])
        let restored = try #require(sessions.first { $0.identifierText == kept })
        // OpenRun does not guess what ran in the session: the login shell starts.
        let shell = try RunningSessionProcess.loginShellFromDirectoryService()
        #expect(restored.name == "Build" && restored.command == [shell])
        // A folder that went away gives the home folder.
        #expect(sessions.allSatisfy { $0.folder == NSHomeDirectory() } && second.log.contains("Started the 2 sessions of the last run again."))
    }
}
