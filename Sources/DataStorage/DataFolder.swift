import Darwin
import Foundation

/// The folder where OpenRun keeps its data as readable JSON files.
///
/// Only the session process writes in it, so no two programs replace a file
/// at the same time. Tests name a temporary folder, so they never touch the
/// data of the user.
public struct DataFolder: Equatable, Sendable {
    /// An absolute path.
    public let path: String

    public init(path: String) {
        self.path = path
    }

    /// The folder that also holds the socket of the session process.
    /// `SocketLocation.defaultPath` in `SessionProtocol` names the same folder,
    /// and a test keeps the two in step.
    public static var defaultPath: String {
        NSHomeDirectory() + "/Library/Application Support/OpenRun"
    }

    public static var `default`: DataFolder { DataFolder(path: defaultPath) }

    /// The path of one file of this folder.
    public func path(of file: DataFile) -> String {
        path + "/" + file.name
    }

    /// Makes the folder when it does not exist, and gives it mode 0700.
    ///
    /// The files hold the folders of the user's projects, and later the
    /// sessions. Other users must not read them or put files of their own
    /// here. A folder that already exists gets mode 0700 too, because the
    /// folder belongs to OpenRun.
    public func create() throws {
        var status = stat()
        if stat(path, &status) != 0 {
            guard errno == ENOENT else { throw DataStorageError.failure(of: "stat") }
            do {
                try FileManager.default.createDirectory(
                    atPath: path,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw DataStorageError.folderNotCreated(path: path)
            }
            return
        }
        guard (status.st_mode & S_IFMT) == S_IFDIR else {
            throw DataStorageError.notAFolder(path: path)
        }
        guard status.st_mode & 0o777 != 0o700 else { return }
        guard chmod(path, 0o700) == 0 else { throw DataStorageError.failure(of: "chmod") }
    }
}
