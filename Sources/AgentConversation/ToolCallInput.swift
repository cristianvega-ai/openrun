/// The complete input of a tool call.
public struct ToolCallInput: Codable, Sendable, Hashable {
    public var identifier: String
    public var name: String
    public var input: JSONValue

    public init(identifier: String, name: String, input: JSONValue) {
        self.identifier = identifier
        self.name = name
        self.input = input
    }
}
