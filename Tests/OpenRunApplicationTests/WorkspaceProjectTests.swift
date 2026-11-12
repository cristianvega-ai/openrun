import AppKit
import ProjectsList
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct WorkspaceProjectTests {
    /// A started workspace and two folders inside the folder of its session process.
    private func start() async throws -> (test: TestWorkspace, app: URL, site: URL) {
        let test = try TestWorkspace()
        let app = test.process.directory.appendingPathComponent("app"), site = test.process.directory.appendingPathComponent("site")
        for folder in [app, site] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        test.workspace.sessionEnvironment = ["HOME": test.process.directory.path, "PATH": "/usr/bin:/bin", "PS1": "test> "]
        test.workspace.start()
        #expect(await waitUntil { test.workspace.connection.hasSessionList })
        return (test, app, site)
    }

    private func projectNames(_ test: TestWorkspace) -> [String] {
        test.workspace.window.projectsList.content.projects.map(\.name)
    }

    @Test func aProjectShowsItsSessionsAndANewSessionStartsInItsFolder() async throws {
        let (test, app, _) = try await start()
        defer { test.stop() }
        let workspace = test.workspace, projects = workspace.window.projectsList
        let outside = try test.createShell()
        _ = try test.process.runCommand(["project", "add", app.path, "--name", "App"])
        #expect(await waitUntil { projectNames(test) == ["App"] && test.shownRows == [outside] })
        let project = try #require(projects.content.projects.first?.identifier)

        projects.select(.project(project))
        workspace.projectsList(projects, didSelect: .project(project))
        #expect(test.shownRows.isEmpty && workspace.window.sessionsList.content.title == "App")
        workspace.newSession()
        #expect(await waitUntil { test.shownRows.count == 1 && workspace.shownSession == test.shownRows.first })
        let shown = try #require(workspace.shownSession)
        let session = try #require(workspace.connection.overview.session(shown))
        #expect(session.projectIdentifier == project && session.folder.hasSuffix("/app"))

        // The shell outside every project has no entry of its own. "All Projects" shows it.
        projects.select(.allSessions)
        workspace.projectsList(projects, didSelect: .allSessions)
        #expect(Set(test.shownRows) == [outside, shown] && workspace.layout.selectedEntry == .allSessions)
    }

    @Test func theUserAddsNamesMovesAndRemovesProjects() async throws {
        let (test, app, site) = try await start()
        defer { test.stop() }
        let workspace = test.workspace, projects = workspace.window.projectsList
        workspace.chooseProjectFolders = { $0([app]) }
        workspace.projectsListDidRequestNewProject(projects)
        #expect(await waitUntil { projectNames(test) == ["app"] && projects.selection != .allSessions })
        let first = try #require(projects.content.projects.first?.identifier)
        #expect(projects.selection == .project(first) && workspace.layout.selectedEntry == .project(first))

        workspace.projectsList(projects, didRequestProjectsAt: [site])
        #expect(await waitUntil { projectNames(test) == ["app", "site"] })
        let second = try #require(projects.content.projects.last?.identifier)
        workspace.projectsList(projects, didRenameProject: second, to: "Web Site")
        workspace.projectsList(projects, didMoveProject: second, toIndex: 0)
        #expect(await waitUntil { projectNames(test) == ["Web Site", "app"] })
        workspace.projectsList(projects, didRemoveProject: second)
        #expect(await waitUntil { projectNames(test) == ["app"] })
        // The first pane goes to "All Projects" when its project went away.
        #expect(projects.selection == .allSessions && workspace.layout.selectedEntry == .allSessions)
    }

    @Test func aFolderThatCannotBeAProjectShowsTheReason() async throws {
        let (test, app, _) = try await start()
        defer { test.stop() }
        var failures: [String] = []
        test.workspace.showFailure = { title, message in failures.append(title + ": " + message) }
        test.workspace.addProjects(at: [app, app.appendingPathComponent("missing")])
        #expect(await waitUntil { failures.count == 1 && projectNames(test) == ["app"] })
        #expect(failures[0].hasPrefix("The project could not be added: "))
    }
}
