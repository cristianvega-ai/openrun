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
        /// A raw client can send an empty command. It names no program, so it
        /// is refused instead of starting the login shell in its place.
        @Test func anEmptyCommandIsRefused() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let reply = try answer(to: .createSession(
                folder: process.directory.path,
                command: [],
                size: SessionSize(columns: 80, rows: 24),
                environment: ["PATH": "/usr/bin:/bin"]
            ), from: process)
            guard case .failure(let failure) = reply else {
                Issue.record("The answer was \(String(describing: reply)), not a failure.")
                return
            }
            #expect(failure.reason == .invalidRequest)
            #expect(try process.listedIdentifiers().isEmpty)
        }

        /// A raw client could set a second entry for a name
        /// that OpenRun sets, by putting "=" in the name, and a NUL cut a name
        /// or a value short without a word. Each is refused with a failure
        /// that names the problem, and no session starts.
        @Test func aValueThatWouldReachTheProgramChangedIsRefused() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let folder = process.directory.path
            let searchPath = ["PATH": "/usr/bin:/bin"]
            let cases: [(folder: String, command: [String], environment: [String: String], problem: String)] = [
                (folder, ["/bin/sh", "-c", "sleep 60"], searchPath.merging(["OPENRUN_SOCKET=/tmp/elsewhere": "value"]) { $1 },
                 "an environment variable name holds an equals sign (=)"),
                (folder, ["/bin/sh", "-c", "sleep 60"], searchPath.merging(["": "value"]) { $1 },
                 "an environment variable has an empty name"),
                (folder, ["/bin/sh", "-c", "sleep 60"], searchPath.merging(["NAME\u{0}HIDDEN": "value"]) { $1 },
                 "an environment variable name holds a NUL character"),
                (folder, ["/bin/sh", "-c", "sleep 60"], searchPath.merging(["NAME": "value\u{0}hidden"]) { $1 },
                 "the value of an environment variable holds a NUL character"),
                (folder, ["/bin/sh", "-c", "sleep 60\u{0}; echo hidden"], searchPath,
                 "argument 2 holds a NUL character"),
                (folder, ["/bin/sh\u{0}/hidden", "-c", "sleep 60"], searchPath,
                 "the program name holds a NUL character"),
                (folder + "\u{0}/hidden", ["/bin/sh", "-c", "sleep 60"], searchPath,
                 "the folder holds a NUL character"),
            ]
            for request in cases {
                let reply = try answer(to: .createSession(
                    folder: request.folder,
                    command: request.command,
                    size: SessionSize(columns: 80, rows: 24),
                    environment: request.environment
                ), from: process)
                guard case .failure(let failure) = reply else {
                    Issue.record("\(request.problem): the answer was \(String(describing: reply)), not a failure.")
                    continue
                }
                #expect(failure.reason == .launchFailed)
                #expect(failure.message == "The program was not started: \(request.problem).")
            }
            #expect(try process.listedIdentifiers().isEmpty)
        }

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
