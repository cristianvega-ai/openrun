import AppKit
import SessionConnection
import SessionProtocol

/// Finds running sessions without making the user interface wait for the socket.
public enum SessionList {
    @MainActor public static func choose(at location: SocketLocation, in window: NSWindow?) async -> UUID? {
        do {
            return await SessionListPanel.choose(try await summaries(at: location), in: window)
        } catch {
            await SessionListPanel.showFailure(String(describing: error), in: window)
            return nil
        }
    }

    static func summaries(
        at location: SocketLocation,
        load: @escaping @Sendable (SocketLocation) throws -> [SessionSummary] = { try SessionClient(location: $0).summaries() }
    ) async throws -> [SessionSummary] {
        try await Task.detached { try load(location) }.value
    }
}
