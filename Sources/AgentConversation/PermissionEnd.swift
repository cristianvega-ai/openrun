/// A permission request ended.
public struct PermissionEnd: Codable, Sendable, Hashable {
    public enum Outcome: String, Codable, Sendable {
        /// The user allowed the call.
        case allowed
        /// The user denied the call.
        case denied
        /// The time limit passed, and the call was denied.
        case timedOut
        /// The request ended without an answer, for example when the
        /// thread stopped, and the call was denied.
        case cancelled
    }

    public var identifier: String
    public var outcome: Outcome
    /// The message that went to the agent with a denial.
    public var message: String?

    public init(identifier: String, outcome: Outcome, message: String? = nil) {
        self.identifier = identifier
        self.outcome = outcome
        self.message = message
    }
}
