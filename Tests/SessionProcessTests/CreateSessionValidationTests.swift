import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

/// Sends one request on a new connection and returns the answer. A watchdog
/// closes the connection after the limit, so a test fails instead of hanging.
private func answer(to request: ClientMessage, from process: RunningSessionProcess, within limit: TimeInterval = 30) throws -> ServerMessage? {
    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
    let watchdog = DispatchWorkItem { connection.shutdown() }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer {
        watchdog.cancel()
        connection.shutdown()
    }
    try connection.greetSessionProcess()
    try connection.send(request)
    return try connection.receive(ServerMessage.self)
}

extension SessionProcessIntegration {
    @Suite struct CreateSessionValidationTests {

        /// No command at all still means the login shell.
        @Test func noCommandStartsTheLoginShell() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let reply = try answer(to: .createSession(
                folder: process.directory.path,
                command: nil,
                size: SessionSize(columns: 80, rows: 24),
                environment: ["PATH": "/usr/bin:/bin"]
            ), from: process)
            guard case .sessionCreated(let summary) = reply else {
                Issue.record("The answer was \(String(describing: reply)), not sessionCreated.")
                return
            }
            #expect(summary.command.count == 1 && summary.command[0].hasPrefix("/"))
        }
    }
}
