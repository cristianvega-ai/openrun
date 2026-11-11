import Darwin
import Foundation

/// Replaces a file in one step, so a reader sees the old content or the new
/// content and never a part of either.
///
/// The new content goes to a temporary file in the same folder, which a
/// rename then puts in the place of the old file. A rename in one folder
/// replaces the name at once. The temporary file is made with mode 0600, so
/// no other user can read it at any moment.
enum AtomicFileWriter {
    /// The end of the name of a temporary file. A crash can leave such a
    /// file, and `DataFolder.create` removes it later.
    static let temporarySuffix = ".writing"

    static func write(_ data: Data, to path: String) throws {
        let folder = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let temporary = folder + "/." + name + "." + UUID().uuidString + temporarySuffix
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw DataStorageError.failure(of: "open") }
        var renamed = false
        defer { if !renamed { unlink(temporary) } }
        do {
            defer { close(descriptor) }
            // The umask can only take rights away, but a mode that is
            // exactly 0600 is the promise of this type.
            guard fchmod(descriptor, 0o600) == 0 else { throw DataStorageError.failure(of: "fchmod") }
            try writeAll(data, to: descriptor)
            // fsync alone leaves the data in the cache of the disk. Without
            // the full flush, a power loss after the rename can leave an
            // empty file under the name.
            if fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 {
                throw DataStorageError.failure(of: "fsync")
            }
        }
        guard rename(temporary, path) == 0 else { throw DataStorageError.failure(of: "rename") }
        renamed = true
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let start = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, start + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw DataStorageError.failure(of: "write")
                }
                offset += count
            }
        }
    }
}
