import AgentConversation

/// Finds the tool call of a permission request in the output of Claude
/// Code, by the name of the tool and its input.
///
/// The request of the hook has no tool call identifier (notes 1.4). The
/// input of the hook is equal to the input of the call in the output.
/// When two calls that wait are equal, the first request takes the oldest
/// call. Claude Code asks for its calls in the order in which they come,
/// and the two calls look the same to the user in any case. A request
/// that matches no call gets nil, and the chat shows it on its own.
public struct ClaudeCodeToolCallMatcher: Sendable {
    /// The most calls that wait at one time. The oldest go first.
    public static let callLimit = 256

    private struct Call: Sendable {
        var identifier: String
        var name: String
        var input: JSONValue
    }

    /// The calls that have their input and no result yet, oldest first.
    private var calls: [Call] = []

    public init() {}

    /// Takes the next event of the output.
    public mutating func observe(_ event: ConversationEvent) {
        switch event.kind {
        case .toolCallInput(let input):
            guard !calls.contains(where: { $0.identifier == input.identifier }) else { return }
            calls.append(Call(identifier: input.identifier, name: input.name, input: input.input))
            if calls.count > Self.callLimit { calls.removeFirst() }
        case .toolCallResult(let result):
            calls.removeAll { $0.identifier == result.identifier }
        case .toolCallRefused(let refusal):
            calls.removeAll { $0.identifier == refusal.identifier }
        case .turnEnded, .processEnded:
            calls = []
        default:
            break
        }
    }

    /// The identifier of the oldest call that waits with this tool and
    /// input. The call is taken, so another request cannot match it.
    public mutating func claim(toolName: String, input: JSONValue) -> String? {
        guard let place = calls.firstIndex(where: { $0.name == toolName && $0.input == input }) else { return nil }
        return calls.remove(at: place).identifier
    }
}
