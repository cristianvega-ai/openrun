import Darwin
import Foundation

/// Moves a file that this build cannot read out of the way.
///
/// The file can hold the only copy of the user's data, for example after a
/// later build wrote it, or after the user changed it by hand. So it is
/// never deleted and never written over. It gets a new name in the same
/// folder, which shows the time, and the caller starts from the defaults.
enum UnreadableFile {
    /// Returns the new path. `settings.json` becomes, for example,
    /// `settings.unreadable-20261110T093000Z.json`.
    static func setAside(_ path: String, at time: Date = Date()) throws -> String {
        let folder = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let fileExtension = (name as NSString).pathExtension
        let stamp = timeStamp(time)
        for attempt in 1...100 {
            let counter = attempt == 1 ? "" : "-\(attempt)"
            var newName = "\(base).unreadable-\(stamp)\(counter)"
            if !fileExtension.isEmpty { newName += "." + fileExtension }
            let newPath = folder + "/" + newName
            // RENAME_EXCL fails when the new name exists, so an earlier
            // unreadable file is never written over.
            if renamex_np(path, newPath, UInt32(RENAME_EXCL)) == 0 { return newPath }
            guard errno == EEXIST else { throw DataStorageError.failure(of: "renamex_np") }
        }
        throw DataStorageError.systemCallFailed(function: "renamex_np", code: EEXIST)
    }

    /// The time in UTC, in the basic form of ISO 8601, which sorts by time
    /// and holds no character that a file name cannot hold.
    static func timeStamp(_ time: Date) -> String {
        var seconds = time_t(time.timeIntervalSince1970)
        var parts = tm()
        gmtime_r(&seconds, &parts)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec
        )
    }
}
