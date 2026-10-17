/// Why the session process refused or could not do a request.
public struct SessionFailure: Codable, Equatable, Sendable, CustomStringConvertible {
    public enum Reason: String, Codable, Sendable {
        /// The client speaks another protocol version.
        case incompatibleProtocol
        /// No session has this identifier.
        case unknownSession
        /// The program could not start.
        case launchFailed
        /// The message does not fit this point of the conversation.
        case invalidRequest
    }

    public var reason: Reason
    public var message: String

    public init(reason: Reason, message: String) {
        self.reason = reason
        self.message = message
    }

    public var description: String {
        message
    }
}
