import AgentThreads
import ClaudeCodeAgent
import Foundation

/// A page of the earlier turns of a thread, from the history file of its
/// agent (proposal 3). The session process reads the file in place and
/// keeps no copy, because the file holds the system prompt and the
/// identifiers of the account.
enum ThreadHistory {
    struct Page: Sendable, Equatable {
        /// The events of whole turns as the JSON that a client gets, oldest first.
        var events: [Data] = []
        /// What the client gives to get the page before this one. Nil at
        /// the start of the history, and for a thread with no history.
        var before: Int?
    }

    /// - Parameters:
    ///   - environment: The environment of the agent, which names the
    ///     folder of the settings of Claude Code.
    ///   - before: The `before` of the page that the client has, or nil
    ///     for the newest page.
    static func page(of record: ThreadRecord, environment: [String: String], before: Int?) throws -> Page {
        guard record.hasConversation, let conversation = UUID(uuidString: record.conversationIdentifier), (before ?? 0) >= 0 else { return Page() }
        var environment = environment
        if let account = record.account { environment["CLAUDE_CONFIG_DIR"] = account.settingsFolder }
        let home = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory())
        let settings = ClaudeCodeHistoryLocation.configurationFolder(environment: environment, homeFolder: home)
        guard let file = ClaudeCodeHistoryLocation.locate(configurationFolder: settings, workingFolder: record.folder, conversationIdentifier: conversation) else {
            return Page()
        }
        let reader = try ClaudeCodeHistoryReader(fileURL: file, before: before.map { UInt64($0) })
        let encoder = JSONEncoder()
        let events = try reader.previousTurns().map { try encoder.encode($0) }
        return Page(events: events, before: reader.hasReachedStart ? nil : Int(reader.cursor))
    }
}
