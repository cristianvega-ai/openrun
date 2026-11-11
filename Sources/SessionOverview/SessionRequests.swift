import Foundation
import SessionConnection
import SessionLaunch
import SessionProtocol
import Synchronization

/// Sends the requests of the app to the session process: a new session,
/// the end or the name of one, a change of the projects or of a setting.
///
/// The requests go out one after the other on a queue of their own,
/// because a request waits for the socket, and the first one can wake the
/// launch agent. Each result comes back on the main thread.
public final class SessionRequests: Sendable {
    private let socket: SocketLocation
    private let queue = DispatchQueue(label: "ai.cristianvega.openrun.requests")
    /// The connection of the last request. Only the queue uses it.
    private let client = Mutex<SessionClient?>(nil)
    private let connect: @Sendable (SocketLocation) throws -> SessionClient

    public convenience init(socket: SocketLocation) {
        self.init(socket: socket) { try SessionClient(location: $0, helloTimeLimit: SessionWake.answerTimeLimit) }
    }

    /// - Parameter connect: Makes a connection. Tests give their own.
    init(socket: SocketLocation, connect: @escaping @Sendable (SocketLocation) throws -> SessionClient) {
        (self.socket, self.connect) = (socket, connect)
    }

    /// Runs `request` with a connection to the session process, and gives
    /// its result to `finish` on the main thread.
    public func perform<Value: Sendable>(
        _ request: @escaping @Sendable (SessionClient) throws -> Value,
        then finish: @escaping @MainActor @Sendable (Result<Value, SessionRequestFailure>) -> Void
    ) {
        queue.async { [self] in
            let result: Result<Value, SessionRequestFailure>
            do { result = .success(try run(request)) } catch { result = .failure(SessionRequestFailure(error)) }
            DispatchQueue.main.async { MainActor.assumeIsolated { finish(result) } }
        }
    }

    private func run<Value>(_ request: (SessionClient) throws -> Value) throws -> Value {
        let kept = client.withLock { $0 }
        do {
            return try attempt(request, with: kept)
        } catch where kept != nil && Self.meansEndedConnection(error) {
            // The session process ended since the last request, so it did
            // not get this one. The next session process gets it.
            return try attempt(request, with: nil)
        }
    }

    private func attempt<Value>(_ request: (SessionClient) throws -> Value, with kept: SessionClient?) throws -> Value {
        do {
            let client = try kept ?? connect(socket)
            self.client.withLock { $0 = client }
            return try request(client)
        } catch {
            // Only a refusal leaves the connection ready for the next request.
            if case SessionConnectionError.requestFailed = error {} else { client.withLock { $0 = nil } }
            throw error
        }
    }

    static func meansEndedConnection(_ error: any Error) -> Bool {
        switch error as? SessionConnectionError {
        case .connectionClosed, .protocolFailure: true
        default: false
        }
    }
}
