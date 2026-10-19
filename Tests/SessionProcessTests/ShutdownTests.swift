import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing


private func processExists(_ identifier: pid_t) -> Bool {
    kill(identifier, 0) == 0 || errno != ESRCH
}

extension SessionProcessIntegration {
    @Suite struct ShutdownTests {

        /// When the wait for the socket failed, the caller got no
        /// object to stop, and the session process ran on for the rest of the
        /// test run.
        @Test func aHarnessStartThatFailsStopsTheProcessItStarted() async throws {
            let started = Mutex<pid_t>(0)
            // A wait of no time at all fails while the process still runs.
            #expect(throws: HarnessError.self) {
                _ = try RunningSessionProcess(readyTimeout: 0) { identifier in started.withLock { $0 = identifier } }
            }
            let identifier = started.withLock { $0 }
            #expect(identifier > 0, "the process did not start")
            if identifier > 0 {
                let ended = await eventually(timeout: .seconds(10)) { !processExists(identifier) }
                #expect(ended, "process \(identifier) still runs")
                // A process that is still there must not outlive the run.
                if !ended { kill(identifier, SIGKILL) }
            }
        }

        @Test func theSocketIsPrivateInsideAPrivateFolder() async throws {
            let process = try RunningSessionProcess(socketRelativePath: "private/socket")
            defer { process.stop() }
            let folderMode = try FileManager.default.attributesOfItem(atPath: process.directory.appendingPathComponent("private").path)[.posixPermissions] as? Int
            let socketMode = try FileManager.default.attributesOfItem(atPath: process.socketPath)[.posixPermissions] as? Int
            #expect(folderMode == 0o700)
            #expect(socketMode == 0o600)
        }
    }
}
