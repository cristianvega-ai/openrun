import AppKit
import SessionProcessHarness
import Testing
@testable import OpenRunApplication

/// The session process after an update of the app: the app tells when
/// another build runs, and only the user restarts it.
@MainActor @Suite(.serialized) struct WorkspaceSessionProcessTests {
    /// A workspace on a session process for which this test process counts as OpenRun.app.
    private func start(bundledBuild: String?) async throws -> (test: TestWorkspace, questions: Questions) {
        let test = try TestWorkspace(process: FakeAgentProcess.start(isApplication: true))
        let questions = Questions()
        test.workspace.readBundledBuild = { bundledBuild }
        test.workspace.confirmRestart = { alert, answer in
            questions.titles.append(alert.messageText)
            answer(questions.agrees)
        }
        test.workspace.start()
        #expect(await waitUntil { test.workspace.connection.hasSessionList })
        return (test, questions)
    }

    @MainActor final class Questions {
        var titles: [String] = []
        var agrees = false
    }

    private var restartItem: NSMenuItem { NSMenuItem(title: "", action: #selector(Workspace.restartSessionProcess(_:)), keyEquivalent: "") }

    @Test func theUserHearsOneTimeOfASessionProcessOfAnotherBuild() async throws {
        let (test, questions) = try await start(bundledBuild: "the-build-of-the-new-app")
        defer { test.stop() }
        let workspace = test.workspace
        #expect(await waitUntil { questions.titles == ["The session process is from another build of OpenRun"] })
        // The user said "Not Now", so the session process runs on, and a new connection asks nothing.
        workspace.statusChanged()
        try await Task.sleep(for: .milliseconds(200))
        #expect(questions.titles.count == 1 && test.process.isRunning && workspace.validateMenuItem(restartItem))
    }

    @Test func theRestartCommandEndsTheSessionProcessAfterAYes() async throws {
        let (test, questions) = try await start(bundledBuild: nil)
        defer { test.stop() }
        let workspace = test.workspace
        // Outside an app bundle, and with the same build, the app asks nothing by itself.
        try await Task.sleep(for: .milliseconds(200))
        #expect(questions.titles.isEmpty && workspace.connection.sessionProcessBuild != nil)
        workspace.restartSessionProcess(nil)
        #expect(questions.titles == ["Restart the session process?"] && test.process.isRunning)
        questions.agrees = true
        workspace.restartSessionProcess(nil)
        let status = await test.process.waitForExit()
        #expect(status == 0 && test.process.log.contains("OpenRun.app asked the session process to end."))
        #expect(await waitUntil { workspace.connection.status != .connected && !workspace.validateMenuItem(restartItem) })
    }
}
