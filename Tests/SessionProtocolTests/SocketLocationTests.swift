import Darwin
import Foundation
import Testing
@testable import SessionProtocol

/// Adds an entry to the access control list of a file or folder, such as
/// "everyone allow add_file", with `chmod +a`.
func addAccessControlEntry(_ entry: String, to path: String) throws {
    #expect(try changeMode(["+a", entry, path]) == 0, "chmod +a '\(entry)' failed")
}

/// Removes a folder after its access control list, whose entries could
/// keep it from being removed.
func removeFolderAndItsAccessControlList(_ path: String) {
    _ = try? changeMode(["-R", "-N", path])
    try? FileManager.default.removeItem(atPath: path)
}

private func changeMode(_ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/chmod")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@Suite struct SocketLocationTests {
    /// The absolute path that `resolve` makes. A folder with a long path pushes
    /// the result over the byte limit, and the error then carries that same
    /// path, so these tests give the same answer from any folder.
    private func absolutePath(flag: String?, environment: [String: String]) throws -> String {
        do {
            return try SocketLocation.resolve(flag: flag, environment: environment).path
        } catch SessionProtocolError.socketPathTooLong(let path, _) {
            return path
        }
    }

    @Test func theDefaultLivesInApplicationSupport() {
        #expect(SocketLocation.defaultPath.hasSuffix("/Library/Application Support/OpenRun/session.socket"))
    }

    @Test func theFlagBeatsTheEnvironmentBeatsTheDefault() throws {
        let environment = ["OPENRUN_SOCKET": "/run/from-environment"]
        #expect(try SocketLocation.resolve(flag: "/run/from-flag", environment: environment).path == "/run/from-flag")
        #expect(try SocketLocation.resolve(flag: nil, environment: environment).path == "/run/from-environment")
        #expect(try SocketLocation.resolve(flag: nil, environment: [:]).path == SocketLocation.defaultPath)
        #expect(try SocketLocation.resolve(flag: "", environment: [:]).isDefault)
    }

    @Test func aPathAtTheLimitWorksAndOneByteMoreFails() throws {
        let limit = SocketLocation.pathByteLimit
        let fits = "/" + String(repeating: "a", count: limit - 1)
        #expect(try SocketLocation(path: fits).path == fits)
        #expect(throws: SessionProtocolError.socketPathTooLong(path: fits + "a", limit: limit)) {
            try SocketLocation(path: fits + "a")
        }
    }

    @Test func theErrorMessageNamesThePathAndTheFix() {
        let error = SessionProtocolError.socketPathTooLong(path: "/very/long", limit: 103)
        #expect(error.description.contains("/very/long"))
        #expect(error.description.contains("--socket"))
    }

    @Test func theFolderIsTheParentOfTheSocketFile() throws {
        #expect(try SocketLocation(path: "/run/openrun/session.socket").folder == "/run/openrun")
    }

    @Test func aRelativePathIsMadeAbsoluteAgainstTheCurrentFolder() throws {
        let current = FileManager.default.currentDirectoryPath as NSString
        #expect(try absolutePath(flag: "session.socket", environment: [:]) == current.appendingPathComponent("session.socket"))
        #expect(try absolutePath(flag: nil, environment: ["OPENRUN_SOCKET": "sub/session.socket"]) == current.appendingPathComponent("sub/session.socket"))
        #expect(try absolutePath(flag: "/run/session.socket", environment: [:]) == "/run/session.socket")
    }

    @Test func aRelativePathWithParentFoldersStaysShort() throws {
        let current = FileManager.default.currentDirectoryPath as NSString
        let parent = current.deletingLastPathComponent as NSString
        let name = current.lastPathComponent
        #expect(try absolutePath(flag: "../\(name)/./session.socket", environment: [:]) == current.appendingPathComponent("session.socket"))
        #expect(try absolutePath(flag: "../other/session.socket", environment: [:]) == parent.appendingPathComponent("other/session.socket"))
    }

    @Test func aBareFileNameLivesInTheCurrentFolder() throws {
        let path = try absolutePath(flag: "session.socket", environment: [:])
        #expect((path as NSString).deletingLastPathComponent == FileManager.default.currentDirectoryPath)
    }

    @Test func theDefaultIsRecognizedInOtherSpellings() throws {
        let home = NSHomeDirectory()
        let file = "/Library/Application Support/OpenRun/session.socket"
        #expect(try SocketLocation(path: home + "/Library/Application Support/OpenRun/./session.socket").isDefault)
        #expect(try SocketLocation(path: home + "/Library/../Library/Application Support/OpenRun/session.socket").isDefault)
        #expect(try SocketLocation(path: "/" + home + "//Library/Application Support//OpenRun/session.socket").isDefault)
        #expect(try SocketLocation(path: home + file).isDefault)
        #expect(try !SocketLocation(path: home + "/Library/Application Support/OpenRun/other.socket").isDefault)
        #expect(try !SocketLocation(path: home + "/Library/Application Support/OpenRun/session.socket/inside").isDefault)
    }

    /// architecture.md promises that a symbolic link spelling counts. The
    /// links live in a temporary folder and lead to folders of the home
    /// folder. Nothing is created in the home folder itself.
    @Test func theDefaultIsRecognizedThroughSymbolicLinks() throws {
        // A short folder, because a socket path may hold only 103 bytes.
        let base = "/tmp/default-links-\(UInt32.random(in: 0...UInt32.max))"
        // Mode 0700, because /tmp is shared and another user must not be able
        // to put a link or a file into the folder.
        try FileManager.default.createDirectory(
            atPath: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(atPath: base) }
        var folderStatus = stat()
        #expect(stat(base, &folderStatus) == 0)
        #expect(folderStatus.st_mode & 0o7777 == 0o700)
        let home = NSHomeDirectory()
        #expect(symlink(home, base + "/home") == 0)
        #expect(symlink(home + "/Library/Application Support", base + "/support") == 0)

        let throughHome = try SocketLocation(path: base + "/home/Library/Application Support/OpenRun/session.socket")
        // The link keeps its name, so only the comparison can see the default.
        #expect(throughHome.path.hasPrefix(base + "/home/"))
        #expect(throughHome.isDefault)
        #expect(try SocketLocation(path: base + "/support/OpenRun/session.socket").isDefault)
        #expect(try !SocketLocation(path: base + "/home/Library/Application Support/OpenRun/other.socket").isDefault)
        #expect(try !SocketLocation(path: base + "/support/session.socket").isDefault)
    }

    // MARK: - Absolute paths

    /// Only a relative path lost its "." and "..", so a
    /// long spelling of a short absolute path failed the length check.
    @Test func anAbsolutePathLosesItsDotsBeforeTheLengthCheck() throws {
        let long = "/run" + String(repeating: "/.", count: 60) + "/openrun//session.socket"
        #expect(long.utf8.count > SocketLocation.pathByteLimit)
        #expect(try SocketLocation(path: long).path == "/run/openrun/session.socket")
        #expect(try SocketLocation(path: "/run/missing/../openrun/./session.socket").path == "/run/openrun/session.socket")
        #expect(try SocketLocation(path: "/../run/session.socket").path == "/run/session.socket")
        #expect(try SocketLocation(path: "/run/openrun/session.socket/").path == "/run/openrun/session.socket")
        let flagged = try SocketLocation.resolve(flag: "/run/./openrun/session.socket", environment: [:])
        #expect(flagged.path == "/run/openrun/session.socket")
    }

    /// A symbolic link keeps its name, so a plain path reaches programs as
    /// the user wrote it. A ".." right after a link climbs out of the folder
    /// that the link leads to, as the system reads it.
    @Test func anAbsolutePathKeepsItsSymbolicLinksAndClimbsOutOfThemAsTheSystemDoes() throws {
        let base = NSTemporaryDirectory() + "links-\(UInt32.random(in: 0...UInt32.max))"
        try FileManager.default.createDirectory(atPath: base + "/real/inner", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        #expect(symlink(base + "/real/inner", base + "/link") == 0)
        #expect(try SocketLocation(path: base + "/link/session.socket").path == base + "/link/session.socket")
        #expect(try SocketLocation(path: base + "//link/./session.socket").path == base + "/link/session.socket")

        let realFolder = try #require(realpath(base + "/real", nil))
        defer { free(realFolder) }
        #expect(try SocketLocation(path: base + "/link/../session.socket").path == String(cString: realFolder) + "/session.socket")
    }

    @Test func aSymbolicLinkResolvesToTheFolderItLeadsTo() throws {
        let base = NSTemporaryDirectory() + "resolve-\(UInt32.random(in: 0...UInt32.max))"
        let folder = base + "/real"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        #expect(symlink(folder, base + "/link") == 0)
        let real = SocketLocation.resolvedPath(folder + "/missing/session.socket")
        #expect(SocketLocation.resolvedPath(base + "/link/missing/session.socket") == real)
        #expect(SocketLocation.resolvedPath(base + "/link/./missing/../missing/session.socket") == real)
        #expect(SocketLocation.resolvedPath(base + "/real/other.socket") != real)
    }

    // MARK: - The folder check

    private func folder(mode: mode_t) throws -> String {
        let path = NSTemporaryDirectory() + "folder-\(UInt32.random(in: 0...UInt32.max))"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        #expect(chmod(path, mode) == 0)
        return path
    }

    @Test func aFolderOfTheUserThatOnlyTheUserCanWritePasses() throws {
        for mode: mode_t in [0o700, 0o755, 0o500] {
            let path = try folder(mode: mode)
            defer { try? FileManager.default.removeItem(atPath: path) }
            #expect(throws: Never.self) { try SocketLocation(path: path + "/session.socket").checkFolder() }
        }
    }

    @Test func aFolderThatOthersCanWriteFailsAndTheMessageNamesIt() throws {
        for mode: mode_t in [0o720, 0o702, 0o1777] {
            let path = try folder(mode: mode)
            defer { try? FileManager.default.removeItem(atPath: path) }
            #expect(throws: SessionProtocolError.socketFolderWritableByOthers(folder: path, mode: mode)) {
                try SocketLocation(path: path + "/session.socket").checkFolder()
            }
            let message = SessionProtocolError.socketFolderWritableByOthers(folder: path, mode: mode).description
            #expect(message.contains(path) && message.contains("--socket"))
        }
    }

    @Test func aFolderOfAnotherUserFails() throws {
        let path = try folder(mode: 0o700)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: SessionProtocolError.socketFolderOfAnotherUser(folder: path, owner: geteuid())) {
            try SocketLocation(path: path + "/session.socket").checkFolder(user: geteuid() &+ 1)
        }
    }

    @Test func aMissingFolderPassesSoThatConnectingReportsIt() throws {
        let path = NSTemporaryDirectory() + "missing-\(UInt32.random(in: 0...UInt32.max))/session.socket"
        #expect(throws: Never.self) { try SocketLocation(path: path).checkFolder() }
    }

    /// A file in the place of the folder passed, and the
    /// start failed later with a bare "Not a directory".
    @Test func aFileInThePlaceOfTheFolderFailsAndTheMessageNamesIt() throws {
        let file = NSTemporaryDirectory() + "plain-file-\(UInt32.random(in: 0...UInt32.max))"
        #expect(FileManager.default.createFile(atPath: file, contents: Data("text".utf8)))
        defer { try? FileManager.default.removeItem(atPath: file) }
        #expect(chmod(file, 0o600) == 0)
        let location = try SocketLocation(path: file + "/session.socket")
        let error = #expect(throws: SessionProtocolError.self) { try location.checkFolder() }
        let message = error?.description ?? ""
        #expect(message.contains(location.folder) && message.contains("is not a folder") && message.contains("--socket"), "\(message)")
    }

    /// The check read the mode only, and an entry of the
    /// access control list could let everyone add and remove files.
    @Test(arguments: ["everyone allow add_file,delete_child", "everyone allow add_subdirectory", "group:staff allow delete_child"])
    func aFolderWhoseAccessControlListLetsOthersChangeItFailsAndTheMessageNamesIt(entry: String) throws {
        let path = try folder(mode: 0o700)
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry(entry, to: path)
        let error = #expect(throws: SessionProtocolError.self) { try SocketLocation(path: path + "/session.socket").checkFolder() }
        let message = error?.description ?? ""
        #expect(message.contains(path) && message.contains("access control list") && message.contains("--socket"), "\(message)")
    }

    @Test func aFolderWhoseAccessControlListOnlyDeniesOrServesTheOwnerPasses() throws {
        let path = try folder(mode: 0o700)
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry("everyone deny delete,add_file,delete_child,writesecurity", to: path)
        try addAccessControlEntry("everyone allow list,search,readattr", to: path)
        try addAccessControlEntry("user:\(NSUserName()) allow add_file,add_subdirectory,delete_child", to: path)
        #expect(throws: Never.self) { try SocketLocation(path: path + "/session.socket").checkFolder() }
    }
}
