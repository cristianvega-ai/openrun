import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The feed of `receiveSessionChanges` (decision of 2026-11-10).
    @Suite struct SessionChangesTests {
        @Test func aWatcherGetsTheListThenEachNewSessionAndEachEnd() async throws {
            try await RunningSessionProcess.run { process in
                let first = try process.createSession(program: ["/bin/sleep", "60"])
                let watcher = try SessionChangeWatcher(process)
                #expect(watcher.initialList.map(\.identifierText) == [first])
                let second = try process.createSession(program: ["/bin/sleep", "60"])
                #expect(watcher.summary(of: second) { $0.command == ["/bin/sleep", "60"] } != nil)
                #expect(try process.runCommand(["kill", second]).status == 0)
                #expect(watcher.waitForEnd(of: second))
            }
        }
    }
}
