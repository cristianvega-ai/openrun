import Darwin

/// A session socket could not be used, or the other side broke the protocol.
public enum SessionProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A Unix socket address holds only a short path.
    case socketPathTooLong(path: String, limit: Int)
    /// A frame announced more bytes than the protocol allows.
    case frameTooLarge(length: Int, limit: Int)
    /// A frame did not follow the format.
    case malformedFrame(reason: String)
    /// A message arrived that does not fit this point of the conversation.
    case unexpectedMessage(description: String)

    public var description: String {
        switch self {
        case .socketPathTooLong(let path, let limit):
            "The socket path is too long: a Unix socket path holds at most \(limit) bytes, and \(path) has \(path.utf8.count). Choose a shorter path with --socket."
        case .frameTooLarge(let length, let limit):
            "A frame of \(length) bytes is larger than the limit of \(limit) bytes."
        case .malformedFrame(let reason):
            "A frame is malformed: \(reason)."
        case .unexpectedMessage(let description):
            "An unexpected message arrived: \(description)."
        }
    }
}
