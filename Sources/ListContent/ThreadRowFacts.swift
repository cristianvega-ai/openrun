import Foundation
import SessionProtocol
import SessionsList
import WindowLayout

/// Makes the row of the second pane for an agent thread from its summary
/// (decisions of 2026-11-10).
public enum ThreadRowFacts {
    /// What the row says while the agent waits for an answer of the user.
    public static let waitsForAnswer = "Waits for your answer"
    /// The title of a thread with no name and no message yet.
    public static let untitled = "New Thread"
    /// The families of models, whose name alone shows in a row.
    static let modelFamilies = ["opus", "sonnet", "haiku", "fable", "mythos"]

    /// - Parameter inView: Whether the user looks at the thread and types
    ///   into it. Its request then shows in the chat, and the row needs no mark.
    public static func display(of row: LayoutRow, thread: ThreadSummary, inView: Bool, home: String) -> SessionRowDisplay {
        let kind = SessionKind.agentThread(agent: agentName(thread.agent), model: shortModelName(thread.model), account: thread.accountName)
        return SessionRowDisplay(
            identifier: row.identifier, title: title(of: thread), folder: FolderText.shown(thread.folder, home: home), kind: kind,
            isInProgress: thread.state == "inProgress", alert: thread.state == "needsUser" && !inView ? waitsForAnswer : nil,
            lastActivity: thread.lastActivityAt, startTime: thread.createdAt)
    }

    /// The name that the user gave, or the start of the first message.
    public static func title(of thread: ThreadSummary) -> String {
        if let name = thread.name, !name.isEmpty { return name }
        if let title = thread.title, !title.isEmpty { return title }
        return untitled
    }

    /// The name of the agent as the app shows it.
    public static func agentName(_ agent: String) -> String {
        switch agent {
        case "claude-code": "Claude Code"
        case "codex": "Codex"
        default: agent
        }
    }

    /// The words of a menu for a model: the family for a name of a
    /// family, such as `opus`, and the name itself for any other model.
    public static func modelTitle(_ model: String) -> String {
        modelFamilies.contains(model.lowercased()) ? shortModelName(model) : model
    }

    /// The words of a menu for a permission mode of Claude Code. They
    /// tell what the agent does, because its own words, such as
    /// `dontAsk`, do not.
    public static func permissionModeTitle(_ mode: String) -> String {
        switch mode {
        case "plan": "Plan Only"
        case "dontAsk": "Rules Only"
        case "default", "manual": "Ask First"
        case "acceptEdits": "Accept Edits"
        case "auto": "Auto"
        default: mode
        }
    }

    /// The short name of a model, such as `Opus` for `claude-opus-5-5`,
    /// so the second line of a row keeps room for the folder.
    public static func shortModelName(_ model: String) -> String {
        let lowercased = model.lowercased()
        guard let family = modelFamilies.first(where: { lowercased.contains($0) }) else { return model }
        return family.prefix(1).uppercased() + family.dropFirst()
    }
}
