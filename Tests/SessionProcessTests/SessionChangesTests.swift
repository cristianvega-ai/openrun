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

        /// Each watcher gets every change. One that leaves, and one that
        /// reads nothing, do not hold up the others.
        @Test func eachWatcherGetsTheChangesWhileOthersLeaveOrReadNothing() async throws {
            try await RunningSessionProcess.run { process in
                let (reading, leaving, silent) = (try SessionChangeWatcher(process), try SessionChangeWatcher(process), try SessionChangeWatcher(process))
                leaving.connection.shutdown()
                var created: [String] = []
                for _ in 0..<5 { created.append(try process.createSession(program: ["/bin/sleep", "60"])) }
                // The changes come in order, so each wait reads past the
                // changes before it.
                for identifier in created { #expect(reading.summary(of: identifier) { _ in true } != nil) }
                for identifier in created {
                    #expect(try process.runCommand(["kill", identifier]).status == 0)
                    #expect(reading.waitForEnd(of: identifier))
                }
                #expect(silent.initialList.isEmpty)
            }
        }

        @Test func aWatchingConnectionTakesNoOtherRequest() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                try watcher.connection.send(ClientMessage.listSessions)
                let answer = watcher.next { if case .failure = $0 { true } else { false } }
                guard case .failure(let failure) = answer else {
                    Issue.record("The session process answered \(String(describing: answer))")
                    return
                }
                #expect(failure.reason == .invalidRequest && failure.message.contains("session changes"))
                // The connection still watches.
                let identifier = try process.createSession(program: ["/bin/sleep", "60"])
                #expect(watcher.summary(of: identifier) { _ in true } != nil)
            }
        }
    }
}
