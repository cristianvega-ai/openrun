import DataStorage
import Foundation

/// Reads and writes `threads.json` in the data folder. The file belongs
/// to this Mac, because a thread names a folder and a conversation that
/// only this Mac has (decision of 2026-11-10).
public struct ThreadStore: Sendable {
    /// The content of the file.
    struct Document: DataDocument {
        static let file = DataFile.threads
        static let format = 1
        static let knownKeys: Set<String> = ["threads"]
        var threads: [ThreadRecord]
    }

    public let dataFolder: DataFolder

    public init(dataFolder: DataFolder = .default) {
        self.dataFolder = dataFolder
    }

    public func save(_ list: ThreadList) throws {
        try dataFolder.create()
        try dataFolder.write(Document(threads: list.threads))
    }

    /// The kept threads, and the new name of a file that could not be
    /// read. A record that the checks refuse, or that repeats an
    /// identifier, is left out, so one bad record does not lose the list.
    public func load() throws -> (list: ThreadList, setAsidePath: String?) {
        let result = try dataFolder.read(Document.self)
        var list = ThreadList()
        for record in result.document?.threads ?? [] { try? list.add(record) }
        if case .setAside(let path) = result { return (list, path) }
        return (list, nil)
    }
}
