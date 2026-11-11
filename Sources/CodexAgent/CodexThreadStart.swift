import AgentConversation

/// The settings of a new or a resumed Codex thread.
///
/// The approval policy is always `untrusted`, so that Codex asks before a
/// command or a change outside the sandbox, and the user answers in
/// OpenRun.
public struct CodexThreadStart: Sendable, Hashable {
    /// The working folder of the thread.
    public var folder: String
    /// The model, or nil for the model of the user's configuration.
    public var model: String?
    /// The reasoning effort, such as `low`, or nil for the configuration.
    public var reasoningEffort: String?
    public var sandbox: CodexSandbox

    public init(folder: String, model: String? = nil, reasoningEffort: String? = nil, sandbox: CodexSandbox = .workspaceWrite) {
        self.folder = folder
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.sandbox = sandbox
    }

    var parameters: [String: JSONValue] {
        var parameters: [String: JSONValue] = [
            "cwd": .string(folder), "approvalPolicy": .string("untrusted"), "sandbox": sandbox.threadValue,
        ]
        if let model { parameters["model"] = .string(model) }
        // The thread has no field for the effort. The configuration value
        // sets it for the thread.
        if let reasoningEffort { parameters["config"] = .object(["model_reasoning_effort": .string(reasoningEffort)]) }
        return parameters
    }
}
