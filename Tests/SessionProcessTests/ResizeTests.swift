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
    }
}
