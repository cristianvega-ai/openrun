import AgentConversation

/// The `system` lines of Claude Code's output.
extension ClaudeCodeLineDecoder {
    /// The most agent tasks that the decoder remembers at one time.
    static let agentTaskLimit = 256

    mutating func systemEvents(_ line: JSONValue) -> [ConversationEventKind]? {
        let subtype = line["subtype"]?.string ?? ""
        switch subtype {
        case "init":
            return [.agentStarted(AgentStart(
                conversationIdentifier: line["session_id"]?.string, model: line["model"]?.string,
                permissionMode: line["permissionMode"]?.string, agentVersion: line["claude_code_version"]?.string,
                workingFolder: line["cwd"]?.string))]
        case "thinking_tokens":
            return [.thinking(Thinking(estimatedTokens: line["estimated_tokens"]?.integer, isComplete: false))]
        case "permission_denied":
            let reasons: [String: ToolCallRefusal.Reason] = ["hook": .user, "rule": .rule, "mode": .mode]
            let reason = line["decision_reason_type"]?.string.map { reasons[$0] ?? .other } ?? .unanswered
            return [.toolCallRefused(ToolCallRefusal(
                identifier: line["tool_use_id"]?.string, toolName: line["tool_name"]?.string ?? "",
                reason: reason, message: line["message"]?.string ?? line["decision_reason"]?.string ?? ""))]
        case "task_started" where line["task_type"]?.string == "local_agent" || line["subagent_type"] != nil:
            guard let identifier = line["task_id"]?.string else { return nil }
            if agentTasks.count >= Self.agentTaskLimit { agentTasks.removeAll() }
            agentTasks.insert(identifier)
            return [.taskStarted(TaskStart(
                identifier: identifier, toolCallIdentifier: line["tool_use_id"]?.string,
                description: line["description"]?.string ?? "", agentType: line["subagent_type"]?.string,
                prompt: line["prompt"]?.string ?? ""))]
        case "task_notification" where agentTasks.contains(line["task_id"]?.string ?? ""):
            let identifier = line["task_id"]?.string ?? ""
            agentTasks.remove(identifier)
            return [.taskEnded(TaskEnd(
                identifier: identifier, toolCallIdentifier: line["tool_use_id"]?.string,
                status: line["status"]?.string ?? "", summary: line["summary"]?.string))]
        case "api_retry":
            let attempt = line["attempt"]?.integer.map { " (attempt \($0))" } ?? ""
            let error = line["error"]?.string.map { ": \($0)" } ?? ""
            return [.notice(Notice(level: .warning, text: "The agent tries the request again\(attempt)\(error)."))]
        case "compact_boundary":
            return [.notice(Notice(level: .information, text: "The agent compacted the conversation."))]
        case "informational":
            guard let text = line["content"]?.string ?? line["message"]?.string else { break }
            return [.notice(Notice(level: .information, text: text))]
        case "status":
            return [.agentStatus(AgentStatus(kind: "system/status", detail: line["status"]?.string))]
        case "hook_started", "hook_response":
            // The outcome tells whether a hook failed, such as the
            // permission hook at its time limit.
            let detail = [line["hook_name"]?.string, line["outcome"]?.string].compactMap(\.self).joined(separator: " ")
            return [.agentStatus(AgentStatus(kind: "system/" + subtype, detail: detail))]
        case "task_started", "task_updated", "task_notification", "task_progress", "commands_changed":
            // A task of a command, such as a long Bash call, shows as its
            // tool call already.
            return [.agentStatus(AgentStatus(kind: "system/" + subtype, detail: line["description"]?.string ?? line["status"]?.string))]
        default:
            break
        }
        return nil
    }
}
