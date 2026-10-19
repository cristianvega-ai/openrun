import Darwin
import SessionProtocol

/// A connection to the session process, after the handshake.
struct SessionClient {
    let connection: MessageConnection

    init(location: SocketLocation) throws {
        do {
            connection = try MessageConnection.connect(to: location)
            try connection.greetSessionProcess()
        } catch SessionProtocolError.systemCallFailed(let function, let code) where function == "connect" && (code == ENOENT || code == ECONNREFUSED) {
            throw CommandLineToolError.failure("No session process answers on \(location.path). Start one with openrun-session, or choose a socket with --socket.")
        } catch let error as SessionProtocolError {
            throw CommandLineToolError.failure("\(error)")
        }
    }

    /// Sends one request and returns the answer. A failure answer becomes an
    /// error.
    func request(_ message: ClientMessage) throws -> ServerMessage {
        do {
            try connection.send(message)
            guard let answer = try connection.receive(ServerMessage.self) else {
                throw CommandLineToolError.failure("The session process closed the connection.")
            }
            if case .failure(let failure) = answer {
                throw CommandLineToolError.failure(failure.message)
            }
            return answer
        } catch let error as SessionProtocolError {
            throw CommandLineToolError.failure("\(error)")
        }
    }

    func summaries() throws -> [SessionSummary] {
        guard case .sessionList(let summaries) = try request(.listSessions) else {
            throw CommandLineToolError.failure("The session process gave an unexpected answer to the list request.")
        }
        return summaries
    }

    /// The session that a typed identifier or identifier start means.
    func session(matching typed: String) throws -> SessionSummary {
        try SessionIdentifierMatch.find(typed, in: summaries())
    }
}
