import AgentConversation

/// A request of Codex to run a command or to change files, while it waits
/// for an answer.
struct CodexApproval {
    let thread: String
    /// The identifier of the request, which the answer gives back.
    let request: CodexRequestIdentifier
    /// The command or file change item that waits.
    let item: String
    let method: String
    let parameters: JSONValue
    /// Declines the request after the time limit.
    let timer: Task<Void, Never>

    static let commandMethod = "item/commandExecution/requestApproval"
    static let fileChangeMethod = "item/fileChange/requestApproval"

    /// The request as the chat shows it: the command and its folder, or
    /// the paths and the diffs from the start of the item.
    func permissionRequest(identifier: String, startedItem: JSONValue?) -> PermissionRequest {
        let reason = parameters["reason"] ?? .null
        guard method == Self.fileChangeMethod else {
            let input = JSONValue.object(["command": parameters["command"] ?? .null, "cwd": parameters["cwd"] ?? .null, "reason": reason])
            return PermissionRequest(identifier: identifier, toolName: "commandExecution", input: input, toolCallIdentifier: item)
        }
        let changes = CodexFileChanges.changes(of: startedItem ?? .null).map { change in
            JSONValue.object(["path": .string(change.path), "kind": .string(change.kind.rawValue), "diff": .string(change.diff)])
        }
        let input = JSONValue.object(["changes": .array(changes), "reason": reason, "grantRoot": parameters["grantRoot"] ?? .null])
        return PermissionRequest(identifier: identifier, toolName: "fileChange", input: input, toolCallIdentifier: item)
    }
}
