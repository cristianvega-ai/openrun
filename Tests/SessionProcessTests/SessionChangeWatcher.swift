import Foundation
import SessionProcessHarness
import SessionProtocol

/// A connection that watches the sessions of a process, as the app does.
final class SessionChangeWatcher {
    let connection: MessageConnection
    /// The list that the session process sent first.
    let initialList: [SessionSummary]

    init(_ process: RunningSessionProcess) throws {
        connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
        _ = try connection.greetSessionProcess(within: .seconds(5))
        try connection.send(ClientMessage.receiveSessionChanges)
        let answer = try connection.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(5)))
        guard case .sessionList(let list) = answer else {
            connection.shutdown()
            throw HarnessError.commandFailed(description: "The session process answered \(String(describing: answer))")
        }
        initialList = list
    }

    deinit {
        connection.shutdown()
    }

    /// Reads until a message matches, and returns it. Nil when none comes
    /// within the time limit, or when the connection ends.
    func next(within limit: Duration = .seconds(15), _ matches: (ServerMessage) -> Bool) -> ServerMessage? {
        let deadline = ContinuousClock.now + limit
        while let message = try? connection.receive(ServerMessage.self, timeLimit: .wholeFrame(by: deadline)) {
            if matches(message) { return message }
        }
        return nil
    }

    /// The first summary of the session that meets the condition.
    func summary(of identifier: String, within limit: Duration = .seconds(15), where condition: (SessionSummary) -> Bool) -> SessionSummary? {
        let message = next(within: limit) { message in
            guard case .sessionChanged(let summary) = message else { return false }
            return summary.identifierText == identifier && condition(summary)
        }
        guard case .sessionChanged(let summary) = message else { return nil }
        return summary
    }

    /// Whether the end of the session comes within the time limit.
    func waitForEnd(of identifier: String, within limit: Duration = .seconds(15)) -> Bool {
        next(within: limit) { $0 == .sessionEnded(identifier: UUID(uuidString: identifier) ?? UUID()) } != nil
    }
}

/// Sends one request on a new connection and returns the answer.
func answer(to request: ClientMessage, from process: RunningSessionProcess) throws -> ServerMessage? {
    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
    defer { connection.shutdown() }
    _ = try connection.greetSessionProcess(within: .seconds(5))
    try connection.send(request)
    return try connection.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(10)))
}

/// The summaries that `listSessions` gives, with every fact.
func listedSummaries(of process: RunningSessionProcess) throws -> [SessionSummary] {
    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
    defer { connection.shutdown() }
    _ = try connection.greetSessionProcess(within: .seconds(5))
    try connection.send(ClientMessage.listSessions)
    guard case .sessionList(let summaries) = try connection.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(5))) else {
        throw HarnessError.commandFailed(description: "The session process sent no list.")
    }
    return summaries
}
