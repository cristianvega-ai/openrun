import Darwin
import Foundation

/// Where the session process listens: the path of a Unix socket.
public struct SocketLocation: Equatable, Sendable {
    /// Always absolute, so it leads to the same file from every folder.
    public let path: String

    /// A Unix socket address holds 104 bytes, and the last one ends the path.
    public static let pathByteLimit = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    /// The folder and file name of the socket when no one chooses another.
    public static var defaultPath: String {
        NSHomeDirectory() + "/Library/Application Support/OpenRun/session.socket"
    }


    /// The folder that holds the socket file.
    public var folder: String {
        (path as NSString).deletingLastPathComponent
    }

    /// Makes a relative path absolute against the current folder, removes
    /// the "." and ".." of every path, and checks that the result fits in a
    /// socket address.
    ///
    /// The session process passes its path to every program as
    /// `OPENRUN_SOCKET`, and those programs run in other folders. A relative
    /// path would lead them elsewhere. Without its "." and "..", a long
    /// spelling of a short path, such as "../other/session.socket" behind
    /// the current folder, does not fail the length check.
    public init(path: String) throws {
        let absolute = path.hasPrefix("/") ? path : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        let standardized = Self.standardizedPath(absolute)
        guard standardized.utf8.count <= Self.pathByteLimit else {
            throw SessionProtocolError.socketPathTooLong(path: standardized, limit: Self.pathByteLimit)
        }
        self.path = standardized
    }

    /// An absolute path without empty, "." and ".." components.
    ///
    /// Symbolic links keep their names, so a path that is already plain
    /// reaches programs as the user wrote it. The system reads a ".." after
    /// a symbolic link as the parent of the folder that the link leads to,
    /// not as the folder that holds the link. So a link right before a ".."
    /// is resolved first, and the path still names the same file. A ".."
    /// after a name that does not exist removes that name.
    static func standardizedPath(_ path: String) -> String {
        var components: [String] = []
        for name in path.split(separator: "/") {
            switch name {
            case ".":
                continue
            case "..":
                let parent = "/" + components.joined(separator: "/")
                var status = stat()
                if lstat(parent, &status) == 0, (status.st_mode & S_IFMT) == S_IFLNK, let resolved = realpath(parent, nil) {
                    components = String(cString: resolved).split(separator: "/").map(String.init)
                    free(resolved)
                }
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(name))
            }
        }
        return "/" + components.joined(separator: "/")
    }
}
