import Darwin
import SessionProtocol

/// A connection to the session process, after the greeting.
public struct SessionClient: Sendable {
    let connection: MessageConnection

    /// Connects to the session process on the socket, and greets it.
    public init(location: SocketLocation) throws {
        try self.init(greeting: Self.connect(to: location))
    }

    /// Greets the session process on an open connection, such as a test's.
    init(greeting connection: MessageConnection) throws {
        try SessionConnectionError.wrapping { try connection.greetSessionProcess() }
        self.connection = connection
    }

    /// This is the one place that learns that no program listens on the
    /// socket. A client that can start the session process does it here,
    /// and then connects again.
    private static func connect(to location: SocketLocation) throws -> MessageConnection {
        do {
            return try MessageConnection.connect(to: location)
        } catch SessionProtocolError.systemCallFailed(let function, let code) where function == "connect" && (code == ENOENT || code == ECONNREFUSED) {
            throw SessionConnectionError.noSessionProcess(socketPath: location.path)
        } catch let error as SessionProtocolError {
            throw SessionConnectionError.protocolFailure(error)
        }
    }
}
