import Foundation

/// A folder as a row or a chat shows it.
public enum FolderText {
    /// The folder with `~` in place of the home folder, such as
    /// `~/Projects/openrun`. Any other folder stays as it is.
    public static func shown(_ folder: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return folder }
        if folder == home { return "~" }
        return folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder
    }

    /// The last name of the folder, such as `openrun`, or `~` for the
    /// home folder and `/` for the root.
    static func lastName(of folder: String, home: String) -> String {
        if folder == home { return "~" }
        let name = (folder as NSString).lastPathComponent
        return name.isEmpty ? folder : name
    }
}
