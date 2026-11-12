import Foundation

/// Install Command-Line Tool: a link to the `openrun` program of the app
/// bundle in a folder of the search path, so the command works in every
/// terminal. In a session of OpenRun it works with no link, because the
/// helper folder of the bundle is first in the search path there.
public struct ToolInstallation: Equatable, Sendable {
    /// The usual folder for the commands of apps. It is in the search
    /// path of each login shell of macOS.
    public static let usualFolder = "/usr/local/bin"

    /// The `openrun` program in the helper folder of the app bundle.
    public let toolPath: String
    /// The folder that gets the link.
    public let folder: String

    public init(toolPath: String, folder: String = ToolInstallation.usualFolder) {
        (self.toolPath, self.folder) = (toolPath, folder)
    }

    /// The installation for the app bundle that holds a program, or nil
    /// when the program is in no bundle with the tool, as in a build
    /// folder of `swift build`.
    public init?(bundlePath: String, folder: String = ToolInstallation.usualFolder) {
        let tool = bundlePath + "/Contents/Helpers/openrun"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return nil }
        self.init(toolPath: tool, folder: folder)
    }

    public var linkPath: String { folder + "/openrun" }

    /// Whether the link exists and names the tool of this bundle.
    public var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == toolPath
    }

    /// Whether this user can make the link. `/usr/local/bin` belongs to
    /// the administrator on most Macs, and it can be missing.
    public var needsAdministrator: Bool {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        if manager.fileExists(atPath: folder, isDirectory: &isFolder) { return !isFolder.boolValue || !manager.isWritableFile(atPath: folder) }
        return !manager.isWritableFile(atPath: (folder as NSString).deletingLastPathComponent)
    }

    /// The command for `/bin/sh` that makes the folder and the link, for
    /// a run with the rights of the administrator. Each path is in single
    /// quotes, so no character of a path is a word of the shell.
    public var shellCommand: String {
        "/bin/mkdir -p \(Self.quoted(folder)) && /bin/ln -sfn \(Self.quoted(toolPath)) \(Self.quoted(linkPath))"
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Makes the link as this user. A link or a file of an older install
    /// at that place goes away first.
    public func install() throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if (try? manager.attributesOfItem(atPath: linkPath)) != nil { try manager.removeItem(atPath: linkPath) }
        try manager.createSymbolicLink(atPath: linkPath, withDestinationPath: toolPath)
    }
}
