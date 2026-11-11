import Foundation
import SessionProtocol

/// One session in the output of `openrun list --json`, a shape that agents
/// can rely on. Every key is always there, with `null` for a fact that the
/// session process does not know. The names are those of the protocol,
/// the identifier is in lower case as people type it, and each time is
/// text in ISO 8601, such as `2026-11-10T09:30:00Z`.
struct ListedSession: Encodable {
    let summary: SessionSummary

    private enum Key: String, CodingKey {
        case identifier, name, title, folder, currentFolder, branch, command, foregroundProgram
        case isInProgress, alert, size, createdAt, lastOutputAt, lastInputAt, projectIdentifier
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(summary.identifierText, forKey: .identifier)
        // An optional value with no content becomes null, so the key stays.
        try container.encode(summary.name, forKey: .name)
        try container.encode(summary.title, forKey: .title)
        try container.encode(summary.folder, forKey: .folder)
        try container.encode(summary.currentFolder, forKey: .currentFolder)
        try container.encode(summary.branch, forKey: .branch)
        try container.encode(summary.command, forKey: .command)
        try container.encode(summary.foregroundProgram, forKey: .foregroundProgram)
        try container.encode(summary.isInProgress, forKey: .isInProgress)
        try container.encode(summary.alert, forKey: .alert)
        try container.encode(summary.size, forKey: .size)
        try container.encode(summary.createdAt, forKey: .createdAt)
        try container.encode(summary.lastOutputAt, forKey: .lastOutputAt)
        try container.encode(summary.lastInputAt, forKey: .lastInputAt)
        // In lower case, as `openrun project list` shows it.
        try container.encode(summary.projectIdentifier.map(SessionSummary.text(for:)), forKey: .projectIdentifier)
    }

    /// The whole output: an object with the list, so that a later version
    /// can add keys beside it.
    static func document(of summaries: [SessionSummary]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(["sessions": summaries.map(ListedSession.init)])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
