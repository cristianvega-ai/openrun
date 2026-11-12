import AgentConversation
import Foundation

/// The command line of the process of a Claude Code thread.
///
/// Every flag is the one that the prototype of 2026-11-10 checked against
/// Claude Code 2.1.322. None drops part of the user's own setup: the
/// user's settings, plugins, MCP servers and CLAUDE.md stay in force.
public struct ClaudeCodeLaunch: Sendable, Hashable {
    public enum Conversation: Sendable, Hashable {
        /// The first start of a thread: OpenRun chooses the identifier.
        case new(UUID)
        /// Every later start of the same conversation.
        case resume(UUID)
    }

    /// The longest time that the hook may hold a permission request: 24
    /// hours, longer than any wait that OpenRun allows.
    public static let hookTimeoutSeconds = 86_400

    public var model: String
    public var permissionMode: ClaudeCodePermissionMode
    public var conversation: Conversation
    /// The program of the `PermissionRequest` hook, an absolute path.
    public var hookCommand: String
    /// The arguments of the hook program.
    public var hookArguments: [String]

    /// Refuses a model name that could pass for a flag, or that holds a
    /// character that no model name has.
    public init(
        model: String, permissionMode: ClaudeCodePermissionMode, conversation: Conversation,
        hookCommand: String, hookArguments: [String]
    ) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:[]/@")
        guard !model.isEmpty, !model.hasPrefix("-"), model.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ClaudeCodeLaunchError.invalidModel
        }
        self.model = model
        self.permissionMode = permissionMode
        self.conversation = conversation
        self.hookCommand = hookCommand
        self.hookArguments = hookArguments
    }

    private var conversationArguments: [String] {
        switch conversation {
        case .new(let identifier): ["--session-id", identifier.uuidString.lowercased()]
        case .resume(let identifier): ["--resume", identifier.uuidString.lowercased()]
        }
    }

    /// The arguments of Claude Code in a terminal session, for Open in
    /// Terminal (proposal 6): the same conversation, model and mode. The
    /// user answers in the terminal, so the run has no hook of OpenRun.
    public var terminalArguments: [String] {
        conversationArguments + ["--model", model, "--permission-mode", permissionMode.rawValue]
    }

    /// The arguments after the program name.
    public var arguments: [String] {
        return [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--replay-user-messages",
            "--model", model, "--permission-mode", permissionMode.rawValue,
            "--permission-prompts", "none", "--settings", settings,
        ] + conversationArguments
    }

    /// The settings that add OpenRun's hook for this run only. Claude Code
    /// merges them with the user's own hooks and writes no file.
    public var settings: String {
        let hook = ["type": JSONValue.string("command"), "command": .string(hookCommand),
                    "args": .array(hookArguments.map(JSONValue.string)),
                    "timeout": .number(Double(Self.hookTimeoutSeconds)), "onFailure": .string("block")]
        let entry = JSONValue.object(["matcher": .string("*"), "hooks": .array([.object(hook)])])
        let value = JSONValue.object(["hooks": .object(["PermissionRequest": .array([entry])])])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
