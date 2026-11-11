import DataStorage
import Darwin
import Foundation

/// Keeps every session process of the tests away from the data folder of
/// the user, `~/Library/Application Support/OpenRun`. A test that wrote
/// there would change the projects and the settings of the real app.
public enum UserDataGuard {
    /// Throws when `openrun-session` with these arguments would keep its
    /// data in the folder of the user: `--data-folder` names it, or the
    /// socket is in it, or no `--socket` is given. Arguments for another
    /// program, such as a shell that becomes the session process, are not
    /// checked.
    public static func check(executable: URL, arguments: [String], currentFolder: URL?) throws {
        guard executable.lastPathComponent == RunningSessionProcess.sessionExecutable.lastPathComponent else { return }
        guard !arguments.contains("--help") else { return }
        let folder: String
        if let index = arguments.firstIndex(of: "--data-folder"), index + 1 < arguments.count {
            folder = arguments[index + 1]
        } else if let index = arguments.firstIndex(of: "--socket"), index + 1 < arguments.count {
            folder = (arguments[index + 1] as NSString).deletingLastPathComponent
        } else {
            folder = DataFolder.defaultPath
        }
        let base = currentFolder?.path ?? FileManager.default.currentDirectoryPath
        let absolute = URL(fileURLWithPath: folder.isEmpty ? "." : folder, relativeTo: URL(fileURLWithPath: base, isDirectory: true)).standardizedFileURL.path
        guard real(absolute) != real(DataFolder.defaultPath) else {
            throw HarnessError.commandFailed(description: "A test may not start a session process whose data folder is \(DataFolder.defaultPath), the data of the user.")
        }
    }

    /// The path with its symbolic links resolved, or the path itself when
    /// it does not exist.
    private static func real(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
