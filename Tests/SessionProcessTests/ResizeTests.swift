import Foundation
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing

/// A connection with a watchdog that closes it after the limit, so a test
/// fails instead of hanging.
private final class WatchedConnection {
    let connection: MessageConnection
    private let watchdog: DispatchWorkItem

    init(socketPath: String, limit: TimeInterval = 30) throws {
        let connection = try MessageConnection.connect(to: SocketLocation(path: socketPath))
        self.connection = connection
        watchdog = DispatchWorkItem { connection.shutdown() }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
        try connection.greetSessionProcess()
    }

    deinit {
        watchdog.cancel()
        connection.shutdown()
    }

    func request(_ message: ClientMessage) throws -> ServerMessage? {
        try connection.send(message)
        return try connection.receive(ServerMessage.self)
    }

    /// Reads until the session process closes the connection.
    func readUntilClosed() {
        while let _ = try? connection.receive(ServerMessage.self) {}
    }

}

/// A program that prints the size of its terminal each time a line arrives.
private let sizeReporter = ["/bin/sh", "-c", "stty -echo; echo ready; while read line; do echo \"size=$(stty size)\"; done"]

extension SessionProcessIntegration {
    @Suite struct ResizeTests {
        /// The terminal model refuses a size above its limit. The program's
        /// pseudo terminal must then keep the old size too, so the program and
        /// the screen that clients see never disagree.
        @Test func aRefusedSizeLeavesTheProgramAndTheScreenAtTheOldSize() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let created = try WatchedConnection(socketPath: process.socketPath).request(.createSession(
                folder: process.directory.path,
                command: sizeReporter,
                size: SessionSize(columns: 80, rows: 24),
                environment: ["PATH": "/usr/bin:/bin"]
            ))
            guard case .sessionCreated(let summary) = created else {
                Issue.record("The session was not created: \(String(describing: created))")
                return
            }
            let identifier = summary.identifierText
            #expect(await process.waitForScreen(of: identifier, containing: "ready"))
            let tooWide = SessionSize(columns: Terminal.maximumGridDimension + 1, rows: 24)

            // An attach at the refused size fails.
            let attachAnswer = try WatchedConnection(socketPath: process.socketPath)
                .request(.attach(identifier: summary.identifier, size: tooWide))
            guard case .failure = attachAnswer else {
                Issue.record("An attach at \(tooWide) was answered with \(String(describing: attachAnswer)).")
                return
            }
            #expect(try process.runCommand(["send", identifier, "--enter"]).status == 0)
            #expect(await process.waitForScreen(of: identifier, containing: "size="))
            #expect(try process.screenText(of: identifier).contains("size=24 80"), "screen: \((try? process.screenText(of: identifier)) ?? "")")

            // A resize to the refused size, from an attached client, changes nothing.
            let attached = try WatchedConnection(socketPath: process.socketPath)
            try attached.connection.send(ClientMessage.attach(identifier: summary.identifier, size: SessionSize(columns: 80, rows: 24)))
            try attached.connection.send(ClientMessage.resize(tooWide))
            try attached.connection.send(ClientMessage.detach)
            attached.readUntilClosed()
            #expect(try process.runCommand(["send", identifier, "--enter"]).status == 0)
            #expect(await eventually { ((try? process.screenText(of: identifier)) ?? "").components(separatedBy: "size=").count == 3 })
            let screen = try process.screenText(of: identifier)
            #expect(!screen.contains(String(tooWide.columns)), "screen: \(screen)")
            #expect(screen.components(separatedBy: "size=24 80").count == 3, "screen: \(screen)")

            // The list reports the size that the program and the screen have.
            guard case .sessionList(let summaries) = try WatchedConnection(socketPath: process.socketPath).request(.listSessions) else {
                Issue.record("The list request failed.")
                return
            }
            #expect(summaries.first?.size == SessionSize(columns: 80, rows: 24))

            // A size within the limit still reaches the program.
            let resized = try WatchedConnection(socketPath: process.socketPath)
            try resized.connection.send(ClientMessage.attach(identifier: summary.identifier, size: SessionSize(columns: 100, rows: 30)))
            try resized.connection.send(ClientMessage.detach)
            resized.readUntilClosed()
            #expect(try process.runCommand(["send", identifier, "--enter"]).status == 0)
            #expect(await process.waitForScreen(of: identifier, containing: "size=30 100"))
        }
    }
}
