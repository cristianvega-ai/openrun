/// A tool call that did not run because something refused it.
public struct ToolCallRefusal: Codable, Sendable, Hashable {
    /// Who or what refused the call.
    public enum Reason: String, Codable, Sendable {
        /// The user, through OpenRun's answer to a permission request, or
        /// a permission hook that failed and so blocked the call.
        case user
        /// A permission rule of the user's settings.
        case rule
        /// The permission mode of the thread.
        case mode
        /// No one answered the request.
        case unanswered
        /// A reason that this version does not know.
        case other
    }

    /// The tool call, when the agent names it.
    public var identifier: String?
    public var toolName: String
    public var reason: Reason
    /// The agent's explanation, or the message of the user's denial.
    public var message: String

    public init(identifier: String?, toolName: String, reason: Reason, message: String) {
        self.identifier = identifier
        self.toolName = toolName
        self.reason = reason
        self.message = message
    }
}
