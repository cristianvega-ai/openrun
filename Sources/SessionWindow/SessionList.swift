import SessionConnection
import SessionProtocol

/// Finds running sessions without making the user interface wait for the socket.
enum SessionList {
    static func summaries(
        at location: SocketLocation,
        load: @escaping @Sendable (SocketLocation) throws -> [SessionSummary] = { try SessionClient(location: $0).summaries() }
    ) async throws -> [SessionSummary] {
        try await Task.detached { try load(location) }.value
    }
}
