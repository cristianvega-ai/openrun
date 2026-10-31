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

@Suite(.serialized) struct LaunchAgentRecoveryTests {
    @MainActor @Test func theRetryMenuRecoversAfterApprovalTimeoutAndSuccess() async throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu, oldWindows = NSApp.windowsMenu
        defer { NSApp.mainMenu = oldMenu; NSApp.windowsMenu = oldWindows }
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zshrc").path, contents: Data())
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let registration = RecoveryRegistration()
        let record = Mutex((questions: [LaunchAgentQuestion](), connections: 0))
        let releaseConnection = DispatchSemaphore(value: 0)
        defer { releaseConnection.signal() }
        let application = OpenRunApplication(socket: try SocketLocation(path: process.socketPath), makeLaunchAgentSetup: {
            LaunchAgentSetup(source: registration, connect: {
                let count = record.withLock { $0.connections += 1; return $0.connections }
                if count == 1 { throw SessionWakeFailure.timedOut(limit: .seconds(15)) }
                releaseConnection.wait()
            }, ask: { question in
                record.withLock { $0.questions.append(question) }
                return false
            })
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

    @MainActor @Test func theRegisterAgainMenuAsksFirstAndThenUnregistersRegistersAndConnects() async throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu, oldWindows = NSApp.windowsMenu
        defer { NSApp.mainMenu = oldMenu; NSApp.windowsMenu = oldWindows }
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zshrc").path, contents: Data())
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let registration = RecoveryRegistration()
        registration.state.withLock { $0.status = .enabled }
        let questions = Mutex<[LaunchAgentQuestion]>([])
        let application = OpenRunApplication(socket: try SocketLocation(path: process.socketPath), makeLaunchAgentSetup: {
            LaunchAgentSetup(source: registration, connect: {
                registration.state.withLock { $0.calls.append("connect") }
            }, ask: { question in
                // The user cancels the first question and agrees to the second.
                questions.withLock { $0.append(question); return $0.count == 2 }
            })
        })
        application.makeNewSession = { .newSession(folder: folder.path, environment: ["HOME": folder.path, "ZDOTDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        defer { application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let file = try #require(MainMenu.make(target: application).item(withTitle: "File")?.submenu)
        let registerAgain = try #require(file.item(withTitle: "Register Session Process Again"))

        #expect(NSApp.sendAction(try #require(registerAgain.action), to: registerAgain.target, from: registerAgain))
        #expect(!application.validateMenuItem(registerAgain))
        await waitForRecovery { application.validateMenuItem(registerAgain) }
        #expect(questions.withLock { $0 } == [.registerAgain])
        #expect(registration.state.withLock { $0.calls }.isEmpty && application.windows.controllers.isEmpty)

        #expect(NSApp.sendAction(try #require(registerAgain.action), to: registerAgain.target, from: registerAgain))
        await waitForRecovery { application.windows.controllers.first?.view != nil }
        #expect(questions.withLock { $0 } == [.registerAgain, .registerAgain])
        #expect(registration.state.withLock { $0.calls } == ["unregister", "register", "connect"])
        #expect(application.validateMenuItem(registerAgain))
    }

    /// The session process takes the connection and never answers hello, so
    /// the setup ends only because of its time limit.
    @MainActor @Test func aSessionProcessThatNeverAnswersHelloEndsTheSetupAndEnablesRetry() async throws {
        _ = NSApplication.shared
        let oldMenu = NSApp.mainMenu, oldWindows = NSApp.windowsMenu
        defer { NSApp.mainMenu = oldMenu; NSApp.windowsMenu = oldWindows }
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = try SocketLocation(path: folder.appendingPathComponent("silent.socket").path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(listener) }
        try #require(location.withAddress { bind(listener, $0, $1) } == 0 && listen(listener, 1) == 0)
        let registration = RecoveryRegistration()
        registration.state.withLock { $0.status = .enabled }
        let questions = Mutex<[LaunchAgentQuestion]>([])
        let application = OpenRunApplication(socket: location, makeLaunchAgentSetup: {
            LaunchAgentSetup(source: registration, connect: {
                try OpenRunApplication.connect(to: location, helloTimeLimit: .seconds(2))
            }, ask: { question in
                questions.withLock { $0.append(question) }
                return false
            })
        })
        let file = try #require(MainMenu.make(target: application).item(withTitle: "File")?.submenu)
        let retry = try #require(file.item(withTitle: "Retry Session Process"))
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(!application.validateMenuItem(retry))
        await waitForRecovery { application.validateMenuItem(retry) }
        #expect(questions.withLock { $0 } == [.failed(detail: "The OpenRun session process did not answer hello within 2 seconds.")])
        #expect(application.windows.controllers.isEmpty && registration.state.withLock { $0.calls }.isEmpty)
    }

    @MainActor private func waitForRecovery(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
