import Foundation

/// The command line that `ClaudeCodeLaunch` gives Claude Code. The fake
/// agent refuses any other, so a test sees a change of the command line
/// that the real agent would not take.
struct FakeAgentArguments {
    static let switches: Set<String> = ["-p", "--verbose", "--include-partial-messages", "--replay-user-messages"]
    static let valueFlags: Set<String> = [
        "--input-format", "--output-format", "--model", "--permission-mode", "--permission-prompts", "--settings",
        "--session-id", "--resume",
    ]
    static let permissionModes: Set<String> = ["default", "acceptEdits", "plan", "dontAsk", "auto"]

    let conversationIdentifier: String
    let isResume: Bool
    /// The command and the arguments of the permission hook of the settings.
    let hook: [String]

    /// Nil when a flag is missing, repeated or unknown, or has a value that
    /// Claude Code would refuse.
    init?(_ arguments: [String]) {
        var seen: Set<String> = []
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted else { return nil }
            if Self.switches.contains(flag) {
                index += 1
                continue
            }
            guard Self.valueFlags.contains(flag), index + 1 < arguments.count else { return nil }
            values[flag] = arguments[index + 1]
            index += 2
        }
        guard seen.isSuperset(of: Self.switches),
              values["--input-format"] == "stream-json", values["--output-format"] == "stream-json",
              values["--permission-prompts"] == "none", values["--model"].map({ !$0.isEmpty }) == true,
              values["--permission-mode"].map(Self.permissionModes.contains) == true,
              values["--settings"].map(Self.hasPermissionHook) == true
        else { return nil }
        hook = Self.permissionHook(values["--settings"] ?? "")
        switch (values["--session-id"], values["--resume"]) {
        case (let identifier?, nil): (conversationIdentifier, isResume) = (identifier, false)
        case (nil, let identifier?): (conversationIdentifier, isResume) = (identifier, true)
        default: return nil
        }
        guard UUID(uuidString: conversationIdentifier) != nil, conversationIdentifier == conversationIdentifier.lowercased()
        else { return nil }
    }

    /// Whether the settings add a command hook for permission requests.
    static func hasPermissionHook(_ settings: String) -> Bool {
        !permissionHook(settings).isEmpty
    }

    /// The command of the hook for permission requests and its arguments,
    /// or nothing when the settings have no such hook.
    static func permissionHook(_ settings: String) -> [String] {
        let value = try? JSONSerialization.jsonObject(with: Data(settings.utf8))
        let entries = ((value as? [String: Any])?["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        let hook = (entries?.first?["hooks"] as? [[String: Any]])?.first
        guard hook?["type"] as? String == "command", let command = hook?["command"] as? String else { return [] }
        return [command] + (hook?["args"] as? [String] ?? [])
    }
}
