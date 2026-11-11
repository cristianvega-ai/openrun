/// A piece of the input of a tool call while the agent writes it.
public struct ToolCallInputDelta: Codable, Sendable, Hashable {
    public var identifier: String
    /// The next piece of the input's JSON text. Alone it is seldom valid
    /// JSON: the pieces only show the input as it grows.
    public var partialInput: String

    public init(identifier: String, partialInput: String) {
        self.identifier = identifier
        self.partialInput = partialInput
    }
}
