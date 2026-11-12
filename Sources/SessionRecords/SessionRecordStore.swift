import DataStorage
import Foundation

/// Reads and writes `sessions.json` in the data folder. The file belongs
/// to this Mac, because a session names a folder of this Mac.
public struct SessionRecordStore: Sendable {
    /// More records than the widest limit of the sessions.
    public static let countLimit = 1_000

    /// The content of the file.
    struct Document: DataDocument {
        static let file = DataFile.sessions
        static let format = 1
        static let knownKeys: Set<String> = ["sessions"]
        var sessions: [SessionRecord]
    }

    public let dataFolder: DataFolder

    public init(dataFolder: DataFolder = .default) {
        self.dataFolder = dataFolder
    }

    public func save(_ records: [SessionRecord]) throws {
        try dataFolder.create()
        try dataFolder.write(Document(sessions: records))
    }

    /// The kept records, oldest first, and the new name of a file that
    /// could not be read. A record that the checks refuse, or that
    /// repeats an identifier, is left out, so one bad record does not
    /// lose the others.
    public func load() throws -> (records: [SessionRecord], setAsidePath: String?) {
        let result = try dataFolder.read(Document.self)
        var (records, known): ([SessionRecord], Set<UUID>) = ([], [])
        for record in result.document?.sessions ?? [] where record.isValid && records.count < Self.countLimit {
            if known.insert(record.identifier).inserted { records.append(record) }
        }
        records.sort { $0.createdAt < $1.createdAt }
        if case .setAside(let path) = result { return (records, path) }
        return (records, nil)
    }
}
