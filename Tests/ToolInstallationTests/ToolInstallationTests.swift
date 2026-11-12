import Foundation
import Testing
import ToolInstallation

/// The tests use a temporary folder. They never touch `/usr/local/bin`.
@Suite struct ToolInstallationTests {
    /// A bundle with a tool, and an empty folder for the link.
    private func makeFolders() throws -> (bundle: String, folder: String, root: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "tool-\(UUID().uuidString)")
        let helpers = root.appending(path: "Open Run's.app/Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: helpers.appending(path: "openrun").path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return (root.appending(path: "Open Run's.app").path, root.appending(path: "bin").path, root)
    }

    @Test func theLinkNamesTheToolOfTheBundleAndReplacesAnOlderOne() throws {
        let (bundle, folder, root) = try makeFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = try #require(ToolInstallation(bundlePath: bundle, folder: folder))
        #expect(installation.toolPath == bundle + "/Contents/Helpers/openrun" && installation.linkPath == folder + "/openrun")
        #expect(!installation.isInstalled && !installation.needsAdministrator)
        try installation.install()
        #expect(installation.isInstalled && FileManager.default.isExecutableFile(atPath: installation.linkPath))
        // A link of an older app at that place goes away.
        try FileManager.default.removeItem(atPath: installation.linkPath)
        try FileManager.default.createSymbolicLink(atPath: installation.linkPath, withDestinationPath: "/old/openrun")
        #expect(!installation.isInstalled)
        try installation.install()
        #expect(installation.isInstalled)
    }

    @Test func aProgramOutsideABundleWithTheToolHasNoInstallation() throws {
        #expect(ToolInstallation(bundlePath: NSTemporaryDirectory() + "no-bundle-\(UUID().uuidString)") == nil)
        #expect(ToolInstallation(toolPath: "/a/openrun").folder == "/usr/local/bin")
    }

    @Test func theCommandForTheAdministratorQuotesEachPath() throws {
        let installation = ToolInstallation(toolPath: "/Applications/Open Run's.app/Contents/Helpers/openrun", folder: "/usr/local/bin")
        #expect(installation.shellCommand
            == #"/bin/mkdir -p '/usr/local/bin' && /bin/ln -sfn '/Applications/Open Run'\''s.app/Contents/Helpers/openrun' '/usr/local/bin/openrun'"#)
        // A folder that this user cannot write needs the administrator.
        #expect(ToolInstallation(toolPath: "/a/openrun", folder: "/System/openrun-test-folder").needsAdministrator)
    }
}
