import Darwin
import Foundation
import SessionLaunch
import SessionProtocol

/// A connection to the session process, after the greeting.
public struct SessionClient: Sendable {
    let connection: MessageConnection
    public let capabilities: ServerCapabilities

    /// Starts the session process when nothing listens on the socket.
    typealias Wake = () throws(SessionWakeFailure) -> Void

    /// Connects to the session process on the socket, and greets it. On
    /// the default socket, launchd starts the session process when needed.
    public init(location: SocketLocation) throws {
        try self.init(location: location, wake: Self.launchAgentWake(for: location))
    }

    /// Like `init(location:)`, for a caller that cannot wait without end for
    /// a session process that accepts the connection and never says hello.
    /// Past the limit, it throws `SessionProtocolError.timedOut` inside
    /// `SessionConnectionError.protocolFailure`.
    public init(location: SocketLocation, helloTimeLimit: Duration) throws {
        try self.init(location: location, wake: Self.launchAgentWake(for: location), helloTimeLimit: helloTimeLimit)
    }

    /// Sends one wake when no session process listens, or when the
    /// connection closes before hello, and then connects once more. A
    /// launch agent that ends because it is idle closes such a connection.
    /// A hello that takes too long is no reason for a wake.
    ///
    /// - Parameter wake: Nil for a socket without a launch agent. Tests pass
    ///   their own, because a test cannot register a launch agent.
    /// - Parameter helloTimeLimit: The time that each hello may take. Nil
    ///   waits as long as it takes.
    init(location: SocketLocation, wake: Wake?, helloTimeLimit: Duration? = nil) throws {
        try self.init(wake: wake) {
            try Self(greeting: Self.connect(to: location), within: helloTimeLimit)
        }
    }

    init(wake: Wake?, connect: () throws -> SessionClient) throws {
        do {
            self = try connect()
        } catch let error as SessionConnectionError where wake != nil && Self.meansNoSessionProcess(error) {
            do {
                try wake?()
            } catch {
                throw SessionConnectionError.wakeFailed(error)
            }
            self = try connect()
        }
    }

    /// Only the default socket belongs to the launch agent.
    static func launchAgentWake(for location: SocketLocation) -> Wake? {
        guard location.isDefault else { return nil }
        return { () throws(SessionWakeFailure) in _ = try SessionWake.wake() }
    }

    private static func meansNoSessionProcess(_ error: SessionConnectionError) -> Bool {
        switch error {
        case .noSessionProcess, .protocolFailure(.connectionClosed): true
        case .protocolFailure(.systemCallFailed(_, let code)): code == ECONNRESET || code == EPIPE || code == ENOTCONN
        default: false
        }
    }

    /// Greets the session process on an open connection, such as a test's.
    init(greeting connection: MessageConnection, within limit: Duration? = nil) throws {
        self.capabilities = try SessionConnectionError.wrapping { try connection.greetSessionProcess(within: limit) }
        self.connection = connection
    }

    /// This is the one place that learns that no program listens on the
    /// socket.
    private static func connect(to location: SocketLocation) throws -> MessageConnection {
        do {
            return try MessageConnection.connect(to: location)
        } catch SessionProtocolError.systemCallFailed(let function, let code) where function == "connect" && (code == ENOENT || code == ECONNREFUSED) {
            throw SessionConnectionError.noSessionProcess(socketPath: location.path)
        } catch let error as SessionProtocolError {
            throw SessionConnectionError.protocolFailure(error)
        }
    }

    /// Sends one request and returns the answer. A failure answer becomes an
    /// error.
    public func request(_ message: ClientMessage) throws -> ServerMessage {
        let answer = try SessionConnectionError.wrapping {
            try connection.send(message)
            return try connection.receive(ServerMessage.self)
        }
        guard let answer else { throw SessionConnectionError.connectionClosed }
        if case .failure(let failure) = answer { throw SessionConnectionError.requestFailed(failure) }
        return answer
    }

    /// Every session that the session process holds.
    public func summaries() throws -> [SessionSummary] {
        guard case .sessionList(let summaries) = try request(.listSessions) else {
            throw SessionConnectionError.unexpectedAnswer(request: "list")
        }
        return summaries
    }

    /// The session that a typed identifier or identifier start means.
    public func session(matching typed: String) throws -> SessionSummary {
        try SessionIdentifierMatch.find(typed, in: summaries())
    }

    /// Attaches the connection to a session, and returns once the snapshot
    /// is there. The connection then belongs to the attachment, so the
    /// client takes no more requests.
    public func attach(to identifier: UUID, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool, waitsForOutputRoom: Bool = false) throws -> SessionAttachment {
        try SessionAttachment.attach(on: connection, to: identifier, size: size, relaysRawOutput: relaysRawOutput, receivesSizeChanges: receivesSizeChanges, waitsForOutputRoom: waitsForOutputRoom)
    }
}
