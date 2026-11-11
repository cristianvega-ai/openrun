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
                for name in ["a\nb", "a\u{202E}b", "a\u{2066}b", "a\u{2028}b"] {
                    #expect(try answer(to: .renameSession(identifier: identifier, name: name), from: process) == .failure(SessionFailure(
                        reason: .invalidRequest,
                        message: "A name holds no control character, no mark of text direction, no line separator, and at most 500 characters."
                    )), "\(name.unicodeScalars.map(\.value))")
                }
                #expect(try answer(to: .renameSession(identifier: identifier, name: "👩\u{200D}💻"), from: process) == .acknowledged)
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
