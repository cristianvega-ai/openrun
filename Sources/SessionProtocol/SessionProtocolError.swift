import Darwin

/// A session socket could not be used, or the other side broke the protocol.
public enum SessionProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A frame announced more bytes than the protocol allows.
    case frameTooLarge(length: Int, limit: Int)

    public var description: String {
        switch self {
        case .frameTooLarge(let length, let limit):
            "A frame of \(length) bytes is larger than the limit of \(limit) bytes."
        }
    }
}
