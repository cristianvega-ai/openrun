import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
import TerminalEmulation

/// Runs `body` and shuts the connection down when it takes longer than
/// `limit`, so a regression makes a test fail instead of hanging `swift test`.
/// Returns whether the limit passed.
private func withTimeLimit<Result>(_ limit: TimeInterval, on connection: MessageConnection, _ body: () throws -> Result) rethrows -> (result: Result, timedOut: Bool) {
    let didTimeOut = Mutex(false)
    let watchdog = DispatchWorkItem {
        didTimeOut.withLock { $0 = true }
        connection.shutdown()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    let result = try body()
    return (result, didTimeOut.withLock { $0 })
}

/// A client written against the socket protocol alone. It sees the exact
/// frames, so tests can check the snapshot and the output after it. Every
/// wait has a time limit.
private final class ProtocolClient {
    let connection: MessageConnection
    let terminal: Terminal
    /// The bytes of the escape sequence or character that the snapshot ended
    /// in the middle of. Empty when the snapshot fell between two sequences.
    let unfinishedBytes: [UInt8]

    /// Attaches to a session and restores its snapshot.
    init(socketPath: String, identifier: String, size: SessionSize = SessionSize(columns: 80, rows: 24)) throws {
        let connection = try MessageConnection.connect(to: SocketLocation(path: socketPath))
        let greeting = try withTimeLimit(30, on: connection) { try connection.greetSessionProcess() }
        if greeting.timedOut { throw ProtocolClientError.unexpected("The hello was not answered in time.") }
        try connection.send(ClientMessage.attach(identifier: UUID(uuidString: identifier)!, size: size))
        guard case .attached = try Self.receive(on: connection, within: 30) else {
            throw ProtocolClientError.unexpected("The first answer to attach was not attached.")
        }
        guard case .snapshot(let bytes) = try Self.receive(on: connection, within: 60) else {
            throw ProtocolClientError.unexpected("The second answer to attach was not a snapshot.")
        }
        let terminal = try TerminalSnapshot(bytes: Array(bytes)).restoreTerminal(scrollbackLimit: 10_000)
        self.connection = connection
        self.terminal = terminal
        unfinishedBytes = try UnfinishedSequence(of: terminal).bytes
    }

    /// One message, or `nil` when the connection closed. Throws when the time
    /// limit passes.
    static func receive(on connection: MessageConnection, within limit: TimeInterval) throws -> ServerMessage? {
        let (message, timedOut) = try withTimeLimit(limit, on: connection) { try connection.receive(ServerMessage.self) }
        if timedOut { throw ProtocolClientError.unexpected("No message arrived in \(limit) seconds.") }
        return message
    }

    /// Applies output to the restored terminal until the program exits.
    /// Returns the exit message.
    func followUntilExit() throws -> SessionExit {
        while let message = try Self.receive(on: connection, within: 60) {
            switch message {
            case .output(let bytes): terminal.write(bytes)
            case .exited(let exit): return exit
            default: continue
            }
        }
        throw ProtocolClientError.unexpected("The connection closed before the program exited.")
    }

    /// Applies output until the plain text satisfies the condition. Throws
    /// when the connection closes or the time limit passes first.
    func follow(until condition: (String) -> Bool) throws {
        while !condition(try text(withScrollback: false)) {
            guard let message = try Self.receive(on: connection, within: 60) else {
                throw ProtocolClientError.unexpected("The connection closed before the screen showed the text.")
            }
            if case .output(let bytes) = message { terminal.write(bytes) }
        }
    }

    func text(withScrollback: Bool) throws -> String {
        String(decoding: try terminal.formatted(.plainText, extent: withScrollback ? .withScrollback : .visible), as: UTF8.self)
    }

    func detach() {
        try? connection.send(ClientMessage.detach)
        connection.shutdown()
    }
}

private enum ProtocolClientError: Error {
    case unexpected(String)
}

/// Attaches again and again until a snapshot holds exactly the unfinished
/// bytes that the test is about, and returns that client. The program has
/// written them and waits, and the session process parses them a moment
/// later, so the first snapshot can still lack them. The wait is on the state
/// of the snapshot itself, not on time.
private func attachWhileTheSnapshotHolds(_ unfinished: [UInt8], process: RunningSessionProcess, identifier: String) async throws -> ProtocolClient {
    let deadline = ContinuousClock.now + .seconds(30)
    var lastSeen: [UInt8] = []
    while ContinuousClock.now < deadline {
        let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
        if client.unfinishedBytes == unfinished { return client }
        lastSeen = client.unfinishedBytes
        client.detach()
        try await Task.sleep(for: .milliseconds(25))
    }
    throw ProtocolClientError.unexpected("No snapshot held the unfinished bytes \(unfinished); the last held \(lastSeen).")
}

/// Receives one message, or `nil` when the connection closes or the time
/// limit passes. A test that waits too long fails instead of hanging.
private func receiveMessage(_ connection: MessageConnection, within limit: TimeInterval) throws -> ServerMessage? {
    let watchdog = DispatchWorkItem { connection.shutdown() }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    return try connection.receive(ServerMessage.self)
}


extension SessionProcessIntegration {
    @Suite struct ReattachTests {
        @Test func outputWrittenWhileNoClientWasAttachedIsInTheSnapshot() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo written-while-detached; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "written-while-detached"))
                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { client.detach() }
                #expect(try client.text(withScrollback: false) == "written-while-detached")
            }
        }

        @Test func theSnapshotCarriesTheScreenAndTheScrollback() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 200; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "200"))
                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { client.detach() }

                let screen = try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines)
                let everything = try process.screenText(of: identifier, includeScrollback: true).trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(try client.text(withScrollback: false) == screen)
                #expect(try client.text(withScrollback: true) == everything)
                #expect(everything.hasPrefix("1\n2\n3\n"))
                #expect(everything.hasSuffix("199\n200"))
            }
        }

        @Test func aReattachedClientShowsTheSameScreenAndScrollback() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 100; echo \"$(printf '\\033[1;31m')bold red$(printf '\\033[0m')\"; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "bold red"))

                let first = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                let screenBefore = try first.text(withScrollback: false)
                let historyBefore = try first.text(withScrollback: true)
                let stylesBefore = try first.terminal.formatted(.virtualTerminalSequences)
                first.detach()

                let second = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { second.detach() }
                #expect(try second.text(withScrollback: false) == screenBefore)
                #expect(try second.text(withScrollback: true) == historyBefore)
                #expect(try second.terminal.formatted(.virtualTerminalSequences) == stylesBefore)
                // Detaching leaves the session running.
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test func aSnapshotTakenInsideAnEscapeSequenceContinuesCorrectly() async throws {
            try await RunningSessionProcess.run { process in
                // The program writes half of a color sequence, then waits for a
                // line of input. A client that attaches now gets a snapshot in the
                // middle of the sequence.
                let script = "stty -echo; printf '\\033[3'; read line; printf '1mRED\\033[0m\\n'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])

                // The snapshot must hold the unfinished bytes. Without them the
                // test would only watch ordinary output, and pass on any code.
                let client = try await attachWhileTheSnapshotHolds([0x1B, 0x5B, 0x33], process: process, identifier: identifier)
                defer { client.detach() }
                #expect(try client.text(withScrollback: false) == "")
                #expect(try process.runCommand(["send", identifier, "--enter", "go"]).status == 0)
                try client.follow { $0.contains("RED") }

                // Broken handling would print the rest of the sequence, "1mRED", as text.
                #expect(try client.text(withScrollback: false) == "RED")
                #expect(try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines) == "RED")
            }
        }

        @Test func aSnapshotTakenInsideACharacterContinuesCorrectly() async throws {
            try await RunningSessionProcess.run { process in
                // The first two of the three bytes of the euro sign.
                let script = "stty -echo; printf '\\342\\202'; read line; printf '\\254 euro\\n'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])

                let client = try await attachWhileTheSnapshotHolds([0xE2, 0x82], process: process, identifier: identifier)
                defer { client.detach() }
                #expect(try process.runCommand(["send", identifier, "--enter", "go"]).status == 0)
                try client.follow { $0.contains("euro") }

                #expect(try client.text(withScrollback: false) == "\u{20AC} euro")
                #expect(try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines) == "\u{20AC} euro")
            }
        }

        @Test(arguments: [50, 400, 1000, 1700])
        func attachingWhileOutputRunsLosesNothingAndRepeatsNothing(millisecondsBeforeAttach: Int) async throws {
            try await RunningSessionProcess.run { process in
                // About three seconds of steady output, so the attach lands in the middle.
                let script = "number=1; while [ $number -le 3000 ]; do echo line-$number; number=$((number+1)); if [ $((number % 20)) -eq 0 ]; then sleep 0.02; fi; done"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                try await Task.sleep(for: .milliseconds(millisecondsBeforeAttach))

                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                let exit = try client.followUntilExit()
                #expect(exit == .exited(status: 0))

                let lines = try client.text(withScrollback: true).split(separator: "\n").map(String.init)
                #expect(lines == (1...3000).map { "line-\($0)" })
            }
        }
    }
}
