import AppKit
import SessionProcessHarness
import Testing
import ToolInstallation
@testable import OpenRunApplication

/// Install Command-Line Tool, with a temporary folder in place of `/usr/local/bin`.
@MainActor @Suite(.serialized) struct WorkspaceToolInstallationTests {
    private let item = NSMenuItem(title: "", action: #selector(Workspace.installCommandLineTool(_:)), keyEquivalent: "")

    @Test func theInstallAsksFirstAndThenMakesTheLink() throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace, folder = test.process.directory
        // The test program is in no app bundle, so the item is off.
        #expect(workspace.toolInstallation == nil && !workspace.validateMenuItem(item))
        let installation = ToolInstallation(toolPath: RunningSessionProcess.commandExecutable.path, folder: folder.appending(path: "bin").path)
        workspace.toolInstallation = installation
        var (questions, results, agrees) = (0, [String](), false)
        workspace.confirmToolInstallation = { _, answer in
            questions += 1
            answer(agrees)
        }
        workspace.tellToolInstallation = { title, _ in results.append(title) }
        workspace.runAsAdministrator = { _ in Issue.record("A folder of the user needs no administrator.") }
        #expect(workspace.validateMenuItem(item))
        workspace.installCommandLineTool(nil)
        #expect(questions == 1 && results.isEmpty && !installation.isInstalled)
        agrees = true
        workspace.installCommandLineTool(nil)
        #expect(installation.isInstalled && results == ["The command openrun is installed"])
    }

    @Test func aFolderOfTheAdministratorGetsTheCommandAndAClosedQuestionTellsNothing() throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.toolInstallation = ToolInstallation(toolPath: "/a/openrun", folder: "/System/openrun-test-folder")
        workspace.confirmToolInstallation = { _, answer in answer(true) }
        var (commands, results) = ([String](), [String]())
        workspace.tellToolInstallation = { title, _ in results.append(title) }
        workspace.runAsAdministrator = { commands.append($0) }
        workspace.installCommandLineTool(nil)
        #expect(commands == ["/bin/mkdir -p '/System/openrun-test-folder' && /bin/ln -sfn '/a/openrun' '/System/openrun-test-folder/openrun'"])
        #expect(results == ["The command openrun is installed"])
        workspace.runAsAdministrator = { _ in throw AdministratorCommandFailure(message: "User canceled.", wasCancelled: true) }
        workspace.installCommandLineTool(nil)
        #expect(results.count == 1)
        workspace.runAsAdministrator = { _ in throw AdministratorCommandFailure(message: "No rights.", wasCancelled: false) }
        workspace.installCommandLineTool(nil)
        #expect(results.last == "The command openrun was not installed")
    }
}
