/// A tool call in a transcript, with its state and its result.
public struct ToolCallItem: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable {
        /// The agent writes the input.
        case preparing
        /// The input is complete, and the call runs or waits for the user.
        case running
        case succeeded
        case failed
        /// The user, a rule or the mode refused the call. See `refusal`.
        case refused
        /// The turn or the process ended before the call did.
        case interrupted
    }

    public var name: String
    public var state: State
    /// The input's JSON text as it streams, cut to the detail limit.
    public var inputText: String
    /// The complete input, when it has come.
    public var input: JSONValue?
    /// The start of the output, cut to the detail limit.
    public var output: String
    /// The length of the whole output in bytes.
    public var outputByteCount: Int
    public var exitCode: Int?
    public var refusal: ToolCallRefusal?

    public init(name: String, state: State = .preparing) {
        self.name = name
        self.state = state
        inputText = ""
        output = ""
        outputByteCount = 0
    }
}
