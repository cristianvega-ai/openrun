import Foundation
@testable import SessionLaunch
@testable import SessionProcess
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
import XPC

extension SessionProcessIntegration {
    /// The launch agent ends itself after a time with no session and no
    /// client. The tests set a short time through the setting for tests.
    @Suite struct IdleExitTests {
        static let setting = "OPENRUN_TEST_IDLE_EXIT_MILLISECONDS"
        static let shortLimit = [setting: "300"]
        /// Five times the short limit.
        static let longerThanTheLimit: Duration = .seconds(1.5)

        @Test func theIdleExitCancelsTheWakeServiceBeforeItClosesTheSocket() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let location = try SocketLocation(path: folder.appendingPathComponent("socket").path)
            let server = try SessionServer(location: location)
            await server.start()
            let service = SessionWakeService(socketPath: location.path)
            defer { service.cancel() }
            let endpoint = service.endpoint
            let first = try XPCSession(endpoint: endpoint)
            try #require(try SessionWake.wake(session: first, timeLimit: .seconds(2)) == location.path)
            let cancellationsBeforeClosing = Mutex<[Bool]>([])
            await IdleExit(environment: [Self.setting: "20"]).wait(for: server) {
                service.cancel()
                let next = try? XPCSession(endpoint: endpoint)
                let answer = next.flatMap { try? SessionWake.wake(session: $0, timeLimit: .seconds(1)) }
                let connection = try? MessageConnection.connect(to: location)
                cancellationsBeforeClosing.withLock { $0.append(answer == nil && connection != nil) }
                connection?.shutdown()
            }
            #expect(cancellationsBeforeClosing.withLock { $0 } == [true])
            #expect(!FileManager.default.fileExists(atPath: location.path))
            #expect(throws: (any Error).self) { try MessageConnection.connect(to: location) }
            await server.shutDown()
        }

        @Test func aLaunchAgentWithNoSessionAndNoClientEndsAfterItsTimeLimit() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let process = try LaunchAgentFlagTests.start(in: folder, environment: Self.shortLimit)
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 10) == 0, "log: \(process.log)")
            #expect(process.log.contains("No session and no client for 0.3 seconds. Ending all sessions."), "log: \(process.log)")
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("socket").path))
        }

        @Test func aClientAndThenASessionKeepTheLaunchAgentRunning() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let process = try LaunchAgentFlagTests.start(in: folder, environment: Self.shortLimit)
            defer { process.stop() }
            let socketPath = folder.appendingPathComponent("socket").path
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            let connection = try MessageConnection.connect(to: SocketLocation(path: socketPath))
            try connection.greetSessionProcess()
            try await Task.sleep(for: Self.longerThanTheLimit)
            #expect(process.isRunning, "the client did not keep the process: \(process.log)")

            let created = try RunningSessionProcess.runOpenrun(["new", "--socket", socketPath, "--", "/bin/sleep", "300"], in: folder)
            try #require(created.status == 0, "\(created.standardError)")
            connection.shutdown()
            try await Task.sleep(for: Self.longerThanTheLimit)
            #expect(process.isRunning, "the session did not keep the process: \(process.log)")

            let identifier = created.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let killed = try RunningSessionProcess.runOpenrun(["kill", identifier, "--socket", socketPath], in: folder)
            #expect(killed.status == 0, "\(killed.standardError)")
            #expect(await process.waitForExit(timeout: 10) == 0, "log: \(process.log)")
        }

        @Test func aProcessThatWasStartedByHandDoesNotEndItself() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let process = try SocketSecurityHarness.StartedSessionProcess(
                arguments: ["--socket", folder.appendingPathComponent("socket").path],
                folder: folder,
                logFile: folder.appendingPathComponent("log"),
                environment: Self.shortLimit
            )
            defer { process.stop() }
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            try await Task.sleep(for: Self.longerThanTheLimit)
            #expect(process.isRunning, "log: \(process.log)")
        }

        @Test func theSettingForTestsShortensTheTimeLimitOfThirtySeconds() {
            #expect(IdleExit(environment: [:]).timeLimit == .seconds(30))
            #expect(IdleExit(environment: [Self.setting: "300"]).timeLimit == .milliseconds(300))
            for refused in ["", "0", "-5", "soon", "3600001", "99999999999999999999"] {
                #expect(IdleExit(environment: [Self.setting: refused]).timeLimit == .seconds(30), "\(refused)")
            }
        }
    }
}
