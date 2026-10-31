import AppKit
import SessionLaunch
import SessionProcessHarness
import SessionProtocol
@testable import SessionWindow
import Synchronization
import Testing
@testable import OpenRunApplication

private final class RecoveryRegistration: LaunchAgentStatusSource {
    let state = Mutex((status: LaunchAgentStatus.requiresApproval, calls: [String]()))
    var status: LaunchAgentStatus { state.withLock { $0.status } }
    func register() throws { state.withLock { $0.calls.append("register") } }
    func unregister() throws { state.withLock { $0.calls.append("unregister") } }
    func openSystemSettings() { state.withLock { $0.calls.append("openSystemSettings") } }
}

extension LaunchAgentSetupTests {
    @MainActor @Test func theRetryMenuRecoversAfterRefusalApprovalAndFailure() async throws {
        _ = NSApplication.shared
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zshrc").path, contents: Data())
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let registration = RecoveryRegistration()
        let record = Mutex((questions: [LaunchAgentQuestion](), connections: 0))
        let releaseConnection = DispatchSemaphore(value: 0)
        defer { releaseConnection.signal() }
        let application = OpenRunApplication(socket: try SocketLocation(path: process.socketPath), runLaunchAgentSetup: {
            LaunchAgentSetup(source: registration, connect: {
                let count = record.withLock { $0.connections += 1; return $0.connections }
                if count == 1 { throw SessionWakeFailure.timedOut(limit: .seconds(15)) }
                releaseConnection.wait()
            }, ask: { question in
                record.withLock { $0.questions.append(question) }
                return false
            }).run()
        })
        application.makeNewSession = { .newSession(folder: folder.path, environment: ["HOME": folder.path, "ZDOTDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        defer { application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let file = try #require(MainMenu.make(target: application).item(withTitle: "File")?.submenu)
        let retry = try #require(file.item(withTitle: "Retry Session Process"))
        #expect(retry.target === application)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await waitForRecovery { application.validateMenuItem(retry) }
        #expect(record.withLock { $0.questions } == [.approvalNeeded])
        #expect(application.windows.controllers.isEmpty)
        _ = application.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(record.withLock { $0.questions } == [.approvalNeeded])

        registration.state.withLock { $0.status = .enabled }
        #expect(NSApp.sendAction(try #require(retry.action), to: retry.target, from: retry))
        await waitForRecovery { record.withLock { $0.connections } == 1 && application.validateMenuItem(retry) }
        #expect(record.withLock { $0.questions } == [.approvalNeeded, .failed(detail: "The OpenRun session process did not answer within 15 seconds.")])
        #expect(application.windows.controllers.isEmpty)

        #expect(NSApp.sendAction(try #require(retry.action), to: retry.target, from: retry))
        await waitForRecovery { record.withLock { $0.connections } == 2 }
        #expect(!application.validateMenuItem(retry))
        application.retrySessionProcess(nil)
        #expect(record.withLock { $0.connections } == 2)
        releaseConnection.signal()
        await waitForRecovery { application.windows.controllers.first?.view != nil }
        #expect(application.windows.controllers.count == 1 && !application.validateMenuItem(retry))
        #expect(registration.state.withLock { $0.calls }.isEmpty)
        #expect(record.withLock { $0.questions.count } == 2)
    }

    @MainActor private func waitForRecovery(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
