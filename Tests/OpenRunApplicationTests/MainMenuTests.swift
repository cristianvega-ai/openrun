import AppKit
import SessionProcessHarness
import SessionProtocol
@testable import SessionWindow
import Testing
import TerminalView
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct MainMenuTests {
    @Test func aWindowControllerStaysUntilItsWindowCloses() throws {
        _ = NSApplication.shared
        let windows = WindowList(socket: try SocketLocation(path: "/tmp/openrun-app-test.socket"))
        windows.open(.runningSession(UUID()))
        let controller = try #require(windows.controllers.first)
        #expect(windows.controllers.count == 1)
        controller.window.close()
        #expect(windows.controllers.isEmpty)
    }

    @Test func startupAndReopenMakeSessionsAndClosingDetaches() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zshrc").path, contents: Data())
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let application = OpenRunApplication(socket: try SocketLocation(path: process.socketPath))
        application.makeNewSession = { .newSession(folder: folder.path, environment: ["HOME": folder.path, "ZDOTDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        defer { application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await wait { application.windows.controllers.first?.view != nil }
        let controller = try #require(application.windows.controllers.first)
        _ = try #require(controller.view)
        let first = try process.listedIdentifiers()
        #expect(first.count == 1)
        controller.window.close()
        let afterClose = try process.listedIdentifiers()
        #expect(application.windows.controllers.isEmpty && afterClose == first)
        #expect(application.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        await wait { application.windows.controllers.first?.view != nil }
        let afterReopen = try process.listedIdentifiers()
        #expect(application.windows.controllers.count == 1 && afterReopen.count == 2)
        application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let afterQuit = try process.listedIdentifiers()
        #expect(application.windows.controllers.isEmpty && afterQuit == afterReopen)
    }

    @Test func theWindowActionsMakeANewSessionOrAttachToAnOldOne() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zshrc").path, contents: Data())
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let location = try SocketLocation(path: process.socketPath)
        let application = OpenRunApplication(socket: location)
        application.makeNewSession = { .newSession(folder: folder.path, environment: ["HOME": folder.path, "ZDOTDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        defer { application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let action = NSMenuItem(title: "New Window", action: #selector(OpenRunApplication.newSession(_:)), keyEquivalent: "n")
        #expect(application.validateMenuItem(action))
        await wait { application.windows.controllers.first?.view != nil }
        let first = try #require(try process.listedIdentifiers().first)
        let identifier = try #require(UUID(uuidString: first))
        application.chooseSession = { socket, _ in
            #expect(socket.path == location.path)
            return identifier
        }
        application.attachToSession(nil)
        await wait { application.windows.controllers.count == 2 && application.windows.controllers.last?.view != nil }
        let afterAttach = try process.listedIdentifiers()
        #expect(application.windows.controllers.count == 2 && afterAttach == [first])
        application.newSession(nil)
        await wait { application.windows.controllers.count == 3 && application.windows.controllers.last?.view != nil }
        let afterNew = try process.listedIdentifiers()
        #expect(application.windows.controllers.count == 3 && afterNew.count == 2)
        application.chooseSession = { _, _ in nil }
        application.attachToSession(nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(application.windows.controllers.count == 3)
    }

    @Test func theMenuHasTheWindowAndTextActions() throws {
        _ = NSApplication.shared
        let oldWindowsMenu = NSApp.windowsMenu
        defer { NSApp.windowsMenu = oldWindowsMenu }
        let application = OpenRunApplication(socket: try SocketLocation(path: "/tmp/openrun-menu-test.socket"))
        let menu = MainMenu.make(target: application)
        #expect(menu.items.map(\.title) == ["OpenRun", "File", "Edit", "View", "Window"])
        let file = try #require(menu.item(withTitle: "File")?.submenu)
        let edit = try #require(menu.item(withTitle: "Edit")?.submenu)
        let view = try #require(menu.item(withTitle: "View")?.submenu)
        #expect(file.item(withTitle: "New Window")?.keyEquivalent == "n")
        #expect(file.item(withTitle: "Attach to Session…")?.target === application)
        #expect(file.item(withTitle: "Close Window")?.keyEquivalent == "w")
        let titles = file.items.map(\.title)
        #expect(titles.firstIndex(of: "Register Session Process Again") == (titles.firstIndex(of: "Retry Session Process") ?? -2) + 1)
        let registerAgain = try #require(file.item(withTitle: "Register Session Process Again"))
        #expect(registerAgain.action == #selector(OpenRunApplication.registerSessionProcessAgain(_:)) && registerAgain.target === application)
        // This application has a nondefault socket and no injected setup, so
        // the item is off. Do not send its action here: without the rule, it
        // would register the real launch agent.
        #expect(!application.validateMenuItem(registerAgain))
        #expect(edit.item(withTitle: "Copy")?.action == Selector(("copy:")))
        #expect(edit.item(withTitle: "Paste")?.action == Selector(("paste:")))
        #expect(edit.item(withTitle: "Select All")?.action == Selector(("selectAll:")) && edit.item(withTitle: "Select All")?.keyEquivalent == "a")
        for (title, action, key) in [
            ("Make Text Bigger", "increaseFontSize:", "="),
            ("Make Text Smaller", "decreaseFontSize:", "-"),
            ("Reset Text Size", "resetFontSize:", "0")
        ] {
            let item = try #require(view.item(withTitle: title))
            #expect(item.action == Selector(action) && item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == .command && item.target == nil)
        }
        #expect(!application.validateMenuItem(try #require(file.item(withTitle: "New Window"))))
    }

    @Test func theStandardNewSessionUsesTheHomeFolder() {
        guard case .newSession(let folder, let environment) = SessionStart.newSessionInHomeFolder() else {
            Issue.record("Expected a new session")
            return
        }
        #expect(folder == NSHomeDirectory())
        #expect(environment["PATH"] == ProcessInfo.processInfo.environment["PATH"])
    }

    private func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            runLoopTurn()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func runLoopTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
}
