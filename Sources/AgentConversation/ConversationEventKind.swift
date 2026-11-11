/// What happened in an agent conversation.
///
/// Each adapter turns its agent's output into these cases, so the session
/// process, the chat and the list of threads need not know the agent.
public enum ConversationEventKind: Codable, Sendable, Hashable {
    case agentStarted(AgentStart)
    case userMessage(UserMessage)
    case turnStarted(TurnStart)
    case agentTextDelta(AgentTextDelta)
    case agentText(AgentText)
    case thinking(Thinking)
    case toolCallStarted(ToolCallStart)
    case toolCallInputDelta(ToolCallInputDelta)
    case toolCallInput(ToolCallInput)
    case toolCallOutput(ToolCallOutput)
    case toolCallResult(ToolCallResult)
    case toolCallRefused(ToolCallRefusal)
    case fileChange(FileChange)
    case taskStarted(TaskStart)
    case taskMessage(TaskMessage)
    case taskEnded(TaskEnd)
    case permissionRequested(PermissionRequest)
    case permissionEnded(PermissionEnd)
    case turnEnded(TurnEnd)
    case usage(UsageReading)
    case notice(Notice)
    case agentStatus(AgentStatus)
    case processEnded(ProcessEnd)
    case unknown(UnknownLine)
}
