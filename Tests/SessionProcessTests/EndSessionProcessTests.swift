import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing

/// The request of the app that ends the session process, as after an update.
@Suite struct EndSessionProcessTests {
    @Test func onlyTheAppEndsTheSessionProcessAndItsSessionsComeBack() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A client that is not the app gets a refusal, and the process goes on.
        let plain = try RunningSessionProcess(directory: folder)
        let location = try SocketLocation(path: plain.socketPath)
        #expect(throws: SessionConnectionError.self) { try SessionClient(location: location).endSessionProcess() }
        #expect(plain.isRunning && !plain.log.contains("asked the session process to end"))
        plain.stop()

        // This test process counts as OpenRun.app for the next session process.
        let requirement = ["--answerer-requirement", "cdhash H\"\(try codeHashOfThisProcess())\""]
        let first = try RunningSessionProcess(directory: folder, logName: "log2", arguments: requirement)
        let session = try first.createSession(program: ["/bin/cat"])
        let records = folder.appendingPathComponent("sessions.json")
        #expect(await eventually { (try? String(contentsOf: records, encoding: .utf8))?.lowercased().contains(session) == true })
        try SessionClient(location: location).endSessionProcess()
        let status = await first.waitForExit()
        #expect(status == 0 && first.log.contains("OpenRun.app asked the session process to end."))
        // The next session process starts the session again.
        let second = try RunningSessionProcess(directory: folder, logName: "log3")
        defer { second.stop() }
        #expect(try second.listedIdentifiers() == [session])
    }
}
