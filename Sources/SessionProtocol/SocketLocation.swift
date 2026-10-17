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

    /// Whether this is the default location, in a folder that OpenRun owns.
    /// Other spellings of the same path count too, such as one through a
    /// symbolic link to the home folder.
    public var isDefault: Bool {
        Self.resolvedPath(path) == Self.resolvedPath(Self.defaultPath)
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

    /// Chooses the socket. The `--socket` flag wins, then `OPENRUN_SOCKET`,
    /// then the default path.
    public static func resolve(flag: String?, environment: [String: String]) throws -> SocketLocation {
        if let flag, !flag.isEmpty { return try SocketLocation(path: flag) }
        if let override = environment[SessionEnvironment.socketName], !override.isEmpty {
            return try SocketLocation(path: override)
        }
        return try SocketLocation(path: defaultPath)
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

    /// The path with its symbolic links, "." and ".." resolved as far as its
    /// folders exist, so two spellings of one file compare equal. The part
    /// that does not exist yet keeps its names.
    static func resolvedPath(_ path: String) -> String {
        var existing = path
        var missing: [String] = []
        while true {
            if let resolved = realpath(existing, nil) {
                defer { free(resolved) }
                var components = (String(cString: resolved) as NSString).pathComponents
                for name in missing {
                    switch name {
                    case ".", "/": continue
                    case "..": if components.count > 1 { components.removeLast() }
                    default: components.append(name)
                    }
                }
                return NSString.path(withComponents: components)
            }
            let parent = (existing as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != existing else { return path }
            missing.insert((existing as NSString).lastPathComponent, at: 0)
            existing = parent
        }
    }
}
