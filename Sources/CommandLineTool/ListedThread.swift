import Foundation
import SessionProtocol

/// One thread in the output of `openrun thread list --json`, a shape that
/// scripts can rely on. Every key is always there, with `null` for a fact
/// that the thread does not have. The names are those of the protocol, the
/// identifier is in lower case as people type it, and each time is text in
/// ISO 8601, as in `openrun list --json`.
struct ListedThread: Encodable {
    let summary: ThreadSummary

    private enum Key: String, CodingKey {
        case identifier, agent, name, title, folder, model, permissionMode, accountName, state
        case isProcessRunning, waitingMessageCount, createdAt, lastActivityAt, projectIdentifier
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(summary.identifierText, forKey: .identifier)
        try container.encode(summary.agent, forKey: .agent)
        // An optional value with no content becomes null, so the key stays.
        try container.encode(summary.name, forKey: .name)
        try container.encode(summary.title, forKey: .title)
        try container.encode(summary.folder, forKey: .folder)
        try container.encode(summary.model, forKey: .model)
        try container.encode(summary.permissionMode, forKey: .permissionMode)
        try container.encode(summary.accountName, forKey: .accountName)
        try container.encode(summary.state, forKey: .state)
        try container.encode(summary.isProcessRunning, forKey: .isProcessRunning)
        try container.encode(summary.waitingMessageCount, forKey: .waitingMessageCount)
        try container.encode(summary.createdAt, forKey: .createdAt)
        try container.encode(summary.lastActivityAt, forKey: .lastActivityAt)
        try container.encode(summary.projectIdentifier.map(SessionSummary.text(for:)), forKey: .projectIdentifier)
    }

    /// The whole output: an object with the list, so that a later version
    /// can add keys beside it.
    static func document(of threads: [ThreadSummary]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(["threads": threads.map(ListedThread.init)])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
