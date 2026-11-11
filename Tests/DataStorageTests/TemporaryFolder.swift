import Foundation

/// A new empty folder for one test, so no test touches the real data folder.
final class TemporaryFolder {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path
        path = base + "/openrun-data-storage-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}
