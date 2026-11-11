/// The agent started to write a call of one of its tools.
public struct ToolCallStart: Codable, Sendable, Hashable {
    /// The agent's identifier of the call, such as `toolu_01…`.
    public var identifier: String
    /// The name of the tool, such as `Bash` or `Edit`.
    public var name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}
