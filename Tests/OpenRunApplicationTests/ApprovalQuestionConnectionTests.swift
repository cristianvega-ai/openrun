import AppKit
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct ApprovalQuestionConnectionTests {
    /// A program in one session types into another one after the user
    /// allows it in the alert of the app.
    @Test func theAppAsksTheUserAndSendsTheAnswer() async throws {
        _ = NSApplication.shared
        let process = try RunningSessionProcess(arguments: ["--answerer-requirement", "cdhash H\"\(try codeHashOfThisProcess())\""])
        defer { process.stop() }
        var titles: [String] = []
        let connection = ApprovalQuestionConnection(socket: try SocketLocation(path: process.socketPath)) { alert in
            titles.append(alert.messageText)
            return .alertSecondButtonReturn
        }
        connection.start()
        let deadline = ContinuousClock.now + .seconds(10)
        while !connection.isConnected, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(connection.isConnected)

        let target = try process.createSession(program: ["/bin/sh"])
        let openrun = "'\(RunningSessionProcess.commandExecutable.path)' --socket '\(process.socketPath)'"
        _ = try process.createSession(program: ["/bin/sh", "-c", "\(openrun) send --enter \(target) 'echo allowed-$((6*7))'; exec sleep 60"])
        #expect(await process.waitForScreen(of: target, containing: "allowed-42"))
        #expect(titles == ["Allow a program to type into another session?"])
    }
}
