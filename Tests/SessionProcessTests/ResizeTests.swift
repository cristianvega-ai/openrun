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

    /// Reads until the program has printed the text, and returns the sizes
    /// that arrived in `sizeChanged` messages before it.
    func sizeChanges(until text: String) throws -> [SessionSize] {
        var sizes: [SessionSize] = []
        var output = ""
        while !output.contains(text), let message = try connection.receive(ServerMessage.self) {
            if case .sizeChanged(let size) = message { sizes.append(size) }
            if case .output(let bytes) = message { output += String(decoding: bytes, as: UTF8.self) }
        }
        #expect(output.contains(text), "the connection ended before \(text)")
        return sizes
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

        /// A client was not told when another client changed
        /// the size of its session.
        @Test func onlyTheOtherClientsThatAskedHearOfANewSize() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: sizeReporter)
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                let session = try #require(UUID(uuidString: identifier))
                var clients: [WatchedConnection] = []
                for asks in [true, true, nil] {
                    let client = try WatchedConnection(socketPath: process.socketPath)
                    guard case .attached = try client.request(.attach(identifier: session, size: SessionSize(columns: 80, rows: 24), receivesSizeChanges: asks)) else {
                        Issue.record("A client did not attach.")
                        return
                    }
                    clients.append(client)
                }
                let (requester, asker, other) = (clients[0], clients[1], clients[2])

                // A resize, then a line for the program. The requester knows its size, and the other client did not ask.
                try requester.connection.send(ClientMessage.resize(SessionSize(columns: 100, rows: 30)))
                try requester.connection.send(ClientMessage.input(Data("\n".utf8)))
                #expect(try asker.sizeChanges(until: "size=30 100") == [SessionSize(columns: 100, rows: 30)])
                #expect(try requester.sizeChanges(until: "size=30 100") == [])
                #expect(try other.sizeChanges(until: "size=30 100") == [])

                // An attach with another size: both clients that asked hear of it.
                let newcomer = try WatchedConnection(socketPath: process.socketPath)
                try newcomer.connection.send(ClientMessage.attach(identifier: session, size: SessionSize(columns: 120, rows: 40)))
                try newcomer.connection.send(ClientMessage.input(Data("\n".utf8)))
                for client in [asker, requester] {
                    #expect(try client.sizeChanges(until: "size=40 120") == [SessionSize(columns: 120, rows: 40)])
                }
                #expect(try other.sizeChanges(until: "size=40 120") == [])
                #expect(try newcomer.sizeChanges(until: "size=40 120") == [])
            }
        }
    }
}
