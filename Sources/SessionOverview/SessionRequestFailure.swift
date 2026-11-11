import SessionConnection

/// Why a request of the app failed, in words that a window can show.
public struct SessionRequestFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    /// Whether the session process answered with a refusal, such as for a
    /// folder that does not exist. Otherwise the connection failed.
    public let wasRefused: Bool

    init(_ error: any Error) {
        message = "\(error)"
        if case SessionConnectionError.requestFailed = error { wasRefused = true } else { wasRefused = false }
    }

    public var description: String { message }
}
