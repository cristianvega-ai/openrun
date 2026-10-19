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
    }
}
