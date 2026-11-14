import DataStorage
import Foundation
import OSLog

/// Reads and writes `account-usage.json` for the app: the last usage
/// reading of each account. The file outlives the threads, the app and
/// the session process, because OpenRun sends no request only to get a
/// new reading (decision of 2026-11-13).
public final class AccountUsageStore: Sendable {
    struct Document: DataDocument {
        static let file = DataFile.accountUsage
        static let format = 1
        static let knownKeys: Set<String> = ["readings"]
        var readings: [AccountUsageReading]
    }

    private let dataFolder: DataFolder
    // A write waits for the disk, so the main thread never does it.
    private let queue = DispatchQueue(label: "ai.cristianvega.openrun.account-usage", qos: .utility)
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "AccountUsage")

    public init(dataFolder: DataFolder) {
        self.dataFolder = dataFolder
    }

    /// The kept readings, or none when there is no file or this build
    /// cannot read it.
    public func load() -> [AccountUsageReading] {
        do {
            return try dataFolder.read(Document.self).document?.readings ?? []
        } catch {
            logger.error("The usage of the accounts could not be read: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    /// Writes the readings soon, after each write that waits before them.
    public func save(_ readings: [AccountUsageReading]) {
        queue.async { [self] in
            do {
                try dataFolder.create()
                try dataFolder.write(Document(readings: readings))
            } catch {
                logger.error("The usage of the accounts could not be saved: \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// Writes each reading that waits before it returns, as a test needs.
    public func finishWrites() {
        queue.sync {}
    }
}
