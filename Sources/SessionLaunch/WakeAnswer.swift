/// The answer of the session process to a wake request.
struct WakeAnswer: Codable, Sendable {
    /// The socket that listens. The answer goes out only after it listens,
    /// so a client can connect at once.
    let socketPath: String
}
