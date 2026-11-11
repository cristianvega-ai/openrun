import AgentConversation

/// Short forms of the events of a conversation for the tests.
enum TestEvents {
    static func user(_ identifier: String, _ text: String, images: Int = 0) -> ConversationEvent {
        ConversationEvent(.userMessage(UserMessage(identifier: identifier, text: text, imageCount: images, isAccepted: true)))
    }

    static func text(_ identifier: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.agentText(AgentText(itemIdentifier: identifier, text: text)))
    }

    static func delta(_ identifier: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.agentTextDelta(AgentTextDelta(itemIdentifier: identifier, text: text)))
    }

    static func tool(_ identifier: String, _ name: String, _ input: [String: String]) -> ConversationEvent {
        ConversationEvent(.toolCallInput(ToolCallInput(identifier: identifier, name: name, input: object(input))))
    }

    static func result(_ identifier: String, _ output: String, isError: Bool = false, exitCode: Int? = nil) -> ConversationEvent {
        ConversationEvent(.toolCallResult(ToolCallResult(identifier: identifier, output: output, isError: isError, exitCode: exitCode)))
    }

    static func fileChange(_ identifier: String, _ path: String, _ diff: String, kind: FileChange.Kind = .modified) -> ConversationEvent {
        ConversationEvent(.fileChange(FileChange(identifier: identifier, toolCallIdentifier: identifier, path: path, kind: kind, diff: diff)))
    }

    static func permission(_ identifier: String, _ tool: String, _ input: [String: String], call: String? = nil) -> ConversationEvent {
        ConversationEvent(.permissionRequested(PermissionRequest(identifier: identifier, toolName: tool, input: object(input), toolCallIdentifier: call)))
    }

    static func permissionEnd(_ identifier: String, _ outcome: PermissionEnd.Outcome, message: String? = nil) -> ConversationEvent {
        ConversationEvent(.permissionEnded(PermissionEnd(identifier: identifier, outcome: outcome, message: message)))
    }

    static func turnEnd(_ outcome: TurnEnd.Outcome = .done, error: String? = nil) -> ConversationEvent {
        ConversationEvent(.turnEnded(TurnEnd(outcome: outcome, errorText: error)))
    }

    static func notice(_ text: String, level: Notice.Level = .information) -> ConversationEvent {
        ConversationEvent(.notice(Notice(level: level, text: text)))
    }

    static func object(_ members: [String: String]) -> JSONValue {
        .object(members.mapValues { .string($0) })
    }
}
