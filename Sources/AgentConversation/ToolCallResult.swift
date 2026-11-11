/// The end of a tool call and what it gave back to the agent.
public struct ToolCallResult: Codable, Sendable, Hashable {
    public var identifier: String
    /// The start of the result that the agent got, cut to a limit.
    public var output: String
    /// The length of the whole result in bytes.
    public var outputByteCount: Int
    /// Whether the call failed or was refused.
    public var isError: Bool
    /// The exit status of a command, when the agent gives it.
    public var exitCode: Int?

    public init(identifier: String, output: String, outputByteCount: Int? = nil, isError: Bool, exitCode: Int? = nil) {
        self.identifier = identifier
        self.output = output
        self.outputByteCount = outputByteCount ?? output.utf8.count
        self.isError = isError
        self.exitCode = exitCode
    }
}
