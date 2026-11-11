import Foundation

/// Where Claude Code keeps the history file of a conversation (notes 1.9):
/// `<configuration folder>/projects/<working folder as a name>/<conversation>.jsonl`.
///
/// The format of the folder is not documented, so `locate` also looks in
/// each project folder when the expected path does not exist.
public enum ClaudeCodeHistoryLocation {
    /// The configuration folder of Claude Code: `CLAUDE_CONFIG_DIR`, or
    /// `.claude` in the home folder.
    public static func configurationFolder(environment: [String: String], homeFolder: URL) -> URL {
        if let folder = environment["CLAUDE_CONFIG_DIR"], !folder.isEmpty {
            return URL(fileURLWithPath: folder, isDirectory: true)
        }
        return homeFolder.appending(path: ".claude", directoryHint: .isDirectory)
    }

    /// The name of the project folder of a working folder. Claude Code
    /// writes each UTF-16 code unit that is not an ASCII letter or digit as
    /// a hyphen, so a character outside the BMP gives two.
    public static func projectFolderName(workingFolder: String) -> String {
        String(String.UnicodeScalarView(workingFolder.utf16.map { unit in
            let isLetterOrDigit = (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
            return isLetterOrDigit ? Unicode.Scalar(UInt8(unit)) : "-"
        }))
    }

    /// The expected history file of a conversation.
    public static func fileURL(configurationFolder: URL, workingFolder: String, conversationIdentifier: UUID) -> URL {
        configurationFolder.appending(path: "projects", directoryHint: .isDirectory)
            .appending(path: projectFolderName(workingFolder: workingFolder), directoryHint: .isDirectory)
            .appending(path: conversationIdentifier.uuidString.lowercased() + ".jsonl", directoryHint: .notDirectory)
    }

    /// The history file that exists: at the expected path, at the path of
    /// the working folder without symbolic links, or in any project
    /// folder, such as when Claude Code shortened a long name. Nil when
    /// there is none.
    public static func locate(configurationFolder: URL, workingFolder: String, conversationIdentifier: UUID) -> URL? {
        let files = FileManager.default
        var folders = [workingFolder]
        if let resolved = realpath(workingFolder, nil) {
            folders.append(String(cString: resolved))
            free(resolved)
        }
        for folder in folders {
            let file = fileURL(configurationFolder: configurationFolder, workingFolder: folder, conversationIdentifier: conversationIdentifier)
            if files.fileExists(atPath: file.path) { return file }
        }
        let projects = configurationFolder.appending(path: "projects", directoryHint: .isDirectory)
        let name = conversationIdentifier.uuidString.lowercased() + ".jsonl"
        let candidates = (try? files.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return candidates.sorted { $0.path < $1.path }.lazy.map { $0.appending(path: name) }.first { files.fileExists(atPath: $0.path) }
    }
}
