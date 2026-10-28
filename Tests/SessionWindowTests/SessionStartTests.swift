import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionWindow

@Suite(.isolatedThread) struct SessionStartTests {
    private func screen(of started: StartedSession) throws -> Terminal {
        try TerminalSnapshot(bytes: Array(started.attachment.snapshot)).restoreTerminal(scrollbackLimit: 10)
    }

    @Test func aNewSessionRunsTheLoginShellInTheFolderAtTheSizeOfTheWindow() async throws {
        try await RunningSessionProcess.run { process in
            let home = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: home) }
            // An empty start file, so the shell reads no file of the person who runs the tests.
            FileManager.default.createFile(atPath: home.appendingPathComponent(".zshrc").path, contents: Data())
            let start = SessionStart.newSession(folder: home.path, environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"])
            let started = try start.attach(at: SocketLocation(path: process.socketPath), size: SessionSize(columns: 90, rows: 30))
            defer { started.attachment.shutdown() }
            #expect(started.summary.folder == home.path)
            #expect(started.summary.command == [try RunningSessionProcess.loginShellFromDirectoryService()])
            #expect(try screen(of: started).size == TerminalSize(columns: 90, rows: 30))
        }
    }

    @Test func aRunningSessionGivesItsScreenAndItsSizeChanges() async throws {
        try await RunningSessionProcess.run { process in
            let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo ready-$((6*7)); exec sleep 60"])
            #expect(await process.waitForScreen(of: identifier, containing: "ready-42"))
            let location = try SocketLocation(path: process.socketPath)
            let started = try SessionStart.runningSession(try #require(UUID(uuidString: identifier))).attach(at: location, size: SessionSize(columns: 70, rows: 20))
            defer { started.attachment.shutdown() }
            #expect(started.summary.identifierText == identifier)
            #expect(String(decoding: try screen(of: started).formatted(.plainText), as: UTF8.self).contains("ready-42"))

            let sizes = AsyncStream<SessionAttachmentEvent>.makeStream()
            started.attachment.startReceiving { sizes.continuation.yield($0) }
            // Another client attaches at another size, and the window hears of it.
            let other = try SessionStart.runningSession(started.summary.identifier).attach(at: location, size: SessionSize(columns: 50, rows: 10))
            defer { other.attachment.shutdown() }
            #expect(await sizes.stream.first { _ in true } == .sizeChanged(SessionSize(columns: 50, rows: 10)))
        }
    }
}
