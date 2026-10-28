import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionWindow

@Suite(.isolatedThread) struct SessionListTests {
    @Test func theListNamesRunningSessionsAndCanBeEmpty() async throws {
        try await RunningSessionProcess.run { process in
            let location = try SocketLocation(path: process.socketPath)
            #expect(try await SessionList.summaries(at: location).isEmpty)
            let identifier = try process.createSession(program: ["/bin/sleep", "60"])
            let sessions = try await SessionList.summaries(at: location)
            #expect(sessions.count == 1 && sessions.first?.identifierText == identifier)
        }
    }

    @Test func aMissingSessionProcessIsAnErrorInsteadOfAnEmptyList() async throws {
        let directory = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = try SocketLocation(path: directory.appendingPathComponent("missing.socket").path)
        await #expect(throws: SessionConnectionError.noSessionProcess(socketPath: location.path)) { try await SessionList.summaries(at: location) }
    }

    @MainActor @Test func theListDoesNotWaitForTheSocketOnTheMainThread() async throws {
        let location = try SocketLocation(path: "/tmp/openrun-list-test.socket")
        let result = try await SessionList.summaries(at: location) { _ in
            #expect(!Thread.isMainThread)
            return []
        }
        #expect(result.isEmpty)
    }

}
