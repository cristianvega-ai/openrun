import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The requests that name a session and raise or clear its alert, from
    /// a program outside every session, such as the app.
    @Suite struct SessionFactRequestTests {
        @Test func aNameAndAnAlertComeAndGo() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let text = try process.createSession(program: ["/bin/sleep", "60"])
                let identifier = try #require(UUID(uuidString: text))
                #expect(try answer(to: .renameSession(identifier: identifier, name: "Release build"), from: process) == .acknowledged)
                #expect(watcher.summary(of: text) { $0.name == "Release build" } != nil)
                #expect(try answer(to: .raiseSessionAlert(identifier: identifier, text: "Look\u{1B}[2J here"), from: process) == .acknowledged)
                let alerted = watcher.summary(of: text) { $0.alert != nil }?.alert
                #expect(alerted?.source == .notifyCommand && alerted?.text == "Look[2J here")
                #expect(try answer(to: .clearSessionAlert(identifier: identifier), from: process) == .acknowledged)
                #expect(watcher.summary(of: text) { $0.alert == nil } != nil)
                // An empty name removes the name, as no name does.
                #expect(try answer(to: .renameSession(identifier: identifier, name: ""), from: process) == .acknowledged)
                #expect(watcher.summary(of: text) { $0.name == nil } != nil)
            }
        }

        @Test func aNameWithAControlCharacterOrAnUnknownSessionIsRefused() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try #require(UUID(uuidString: try process.createSession(program: ["/bin/sleep", "60"])))
                guard case .failure(let refusal) = try answer(to: .renameSession(identifier: identifier, name: "a\nb"), from: process) else {
                    Issue.record("A name with a line break was taken.")
                    return
                }
                #expect(refusal.reason == .invalidRequest)
                for request in [ClientMessage.renameSession(identifier: UUID(), name: "x"), .raiseSessionAlert(identifier: UUID(), text: "x"), .clearSessionAlert(identifier: UUID())] {
                    guard case .failure(let failure) = try answer(to: request, from: process) else {
                        Issue.record("\(request) found a session.")
                        continue
                    }
                    #expect(failure.reason == .unknownSession)
                }
            }
        }

        @Test func theGreetingOffersTheChanges() async throws {
            try await RunningSessionProcess.run { process in
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                #expect(try connection.greetSessionProcess(within: .seconds(5)).sessionChanges)
            }
        }
    }
}
