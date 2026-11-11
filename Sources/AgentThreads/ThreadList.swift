import Foundation
import UntrustedText

/// The threads that OpenRun keeps, oldest first. Each way in checks the
/// values, because a client such as the tool gives them and the lists of
/// the app show them.
public struct ThreadList: Equatable, Sendable {
    /// More threads than a user keeps, and few enough for one small file.
    public static let countLimit = 1_000
    public static let nameLengthLimit = 100
    static let wordLengthLimit = 100
    static let folderLengthLimit = 4_096

    public private(set) var threads: [ThreadRecord]

    public init() {
        threads = []
    }

    public func thread(_ identifier: UUID) -> ThreadRecord? {
        threads.first { $0.identifier == identifier }
    }

    /// Adds a thread at the end.
    public mutating func add(_ record: ThreadRecord) throws {
        guard threads.count < Self.countLimit else { throw ThreadListError.tooManyThreads(limit: Self.countLimit) }
        guard thread(record.identifier) == nil else { throw ThreadListError.duplicateThread(record.identifier) }
        threads.append(try Self.checked(record))
    }

    public mutating func remove(_ identifier: UUID) throws {
        guard let index = threads.firstIndex(where: { $0.identifier == identifier }) else { throw ThreadListError.unknownThread(identifier) }
        threads.remove(at: index)
    }

    /// Changes one thread. The changed record passes the same checks as a
    /// new one.
    public mutating func update(_ identifier: UUID, _ change: (inout ThreadRecord) -> Void) throws {
        guard let index = threads.firstIndex(where: { $0.identifier == identifier }) else { throw ThreadListError.unknownThread(identifier) }
        var record = threads[index]
        change(&record)
        threads[index] = try Self.checked(record)
    }

    /// The record with its texts in order, or the reason why it is refused.
    static func checked(_ record: ThreadRecord) throws -> ThreadRecord {
        var record = record
        record.name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if record.name?.isEmpty == true { record.name = nil }
        if let name = record.name, !PlainName.isValid(name, lengthLimit: nameLengthLimit) { throw ThreadListError.invalidName }
        guard record.folder.hasPrefix("/"), record.folder.utf8.count <= folderLengthLimit, !record.folder.unicodeScalars.contains(where: { $0.value == 0 })
        else { throw ThreadListError.invalidFolder }
        guard isWord(record.model) else { throw ThreadListError.invalidModel }
        guard isWord(record.permissionMode) else { throw ThreadListError.invalidPermissionMode }
        return record
    }

    /// A model or a mode: a short word that cannot pass for a flag of the agent.
    static func isWord(_ text: String) -> Bool {
        let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:[]/@"
        return !text.isEmpty && text.count <= wordLengthLimit && !text.hasPrefix("-") && text.allSatisfy(allowed.contains)
    }
}
