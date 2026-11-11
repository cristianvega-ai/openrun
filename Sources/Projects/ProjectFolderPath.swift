import Darwin
import Foundation

/// The one spelling of a project's folder, so that two spellings of one
/// folder compare equal and a folder holds another only by whole names.
public enum ProjectFolderPath {
    /// Makes a folder that the user typed absolute and standard, and
    /// resolves its symbolic links.
    ///
    /// `~` and `~/` start in `homeFolder`. A relative path starts in
    /// `currentFolder`, the folder of the program that asks, because the
    /// session process runs in another folder. The links are resolved
    /// because the session process learns the folder of a session from the
    /// system, which always gives the real path, such as
    /// `/private/tmp/work` for `/tmp/work`.
    ///
    /// - Throws: `ProjectListError.relativeFolder`,
    ///   `ProjectListError.folderDoesNotExist` or
    ///   `ProjectListError.notAFolder`.
    public static func resolve(_ path: String, homeFolder: String, currentFolder: String?) throws -> String {
        var absolute = path
        if path == "~" || path.hasPrefix("~/") {
            absolute = homeFolder + path.dropFirst()
        } else if !path.hasPrefix("/") {
            guard let currentFolder, currentFolder.hasPrefix("/") else {
                throw ProjectListError.relativeFolder(path: path)
            }
            absolute = currentFolder + "/" + path
        }
        guard let resolved = realpath(absolute, nil) else {
            if errno == ENOTDIR { throw ProjectListError.notAFolder(path: standardized(absolute) ?? absolute) }
            throw ProjectListError.folderDoesNotExist(path: standardized(absolute) ?? absolute)
        }
        defer { free(resolved) }
        let real = String(cString: resolved)
        var status = stat()
        guard stat(real, &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else {
            throw ProjectListError.notAFolder(path: real)
        }
        return real
    }

    /// An absolute path without empty, "." and ".." names and without a
    /// slash at the end, or `nil` for a relative path. It reads no file, so
    /// a ".." removes the name before it.
    public static func standardized(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return "/" + components(of: path).joined(separator: "/")
    }

    /// The names of an absolute path, after "." and ".." are applied.
    static func components(of path: String) -> [Substring] {
        var names: [Substring] = []
        for name in path.split(separator: "/") {
            switch name {
            case ".": continue
            case "..": if !names.isEmpty { names.removeLast() }
            default: names.append(name)
            }
        }
        return names
    }

    /// Whether `folder` is `other` or holds it. Names compare whole, so
    /// `/work/app` does not hold `/work/application`.
    static func holds(_ folder: [Substring], _ other: [Substring]) -> Bool {
        folder.count <= other.count && other.starts(with: folder)
    }
}
