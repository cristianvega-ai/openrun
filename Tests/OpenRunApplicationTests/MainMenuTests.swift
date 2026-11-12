import AppKit
import SessionProcessHarness
import SessionPane
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct MainMenuTests {
    private let launch = Notification(name: NSApplication.didFinishLaunchingNotification)

    /// An application on the session process of a test workspace.
    private func makeApplication(_ test: TestWorkspace) -> OpenRunApplication {
        // An empty start file keeps the login shell of the first session quiet.
        FileManager.default.createFile(atPath: test.process.directory.appendingPathComponent(".zshrc").path, contents: Data())
        return OpenRunApplication(socket: test.workspace.socket, workspace: test.workspace)
    }

    @Test func theMenuHasTheSessionTheWindowAndTheTextCommands() async throws {
        let oldWindowsMenu = NSApplication.shared.windowsMenu
        defer { NSApp.windowsMenu = oldWindowsMenu }
        let test = try TestWorkspace()
        defer { test.stop() }
        let application = makeApplication(test), workspace = test.workspace
        let menu = MainMenu.make(target: application)
        #expect(menu.items.map(\.title) == ["OpenRun", "File", "Edit", "View", "Session", "Window"])
        func items(_ title: String) throws -> [NSMenuItem] { try #require(menu.item(withTitle: title)?.submenu).items }
        func key(_ item: NSMenuItem) -> String { (item.keyEquivalentModifierMask.contains(.shift) ? "shift-" : "") + item.keyEquivalent }
        let file = try items("File"), session = try items("Session")
        #expect(file.map(\.title) == ["New Session", "New Thread", "New Session With", "", "Close Session", "Close Window", "", "Retry Session Process", "Register Session Process Again"])
        #expect(file.map(key) == ["n", "t", "", "", "w", "shift-w", "", "", ""])
        #expect(file[0].target === workspace && file[1].target === workspace && file[4].target === workspace && file[5].target == nil && file[8].target === application)
        #expect(session.map(\.title) == ["Rename…", "", "Next Session", "Previous Session"] && session.map(key) == ["", "", "shift-]", "shift-["])
        #expect(try items("View").map(\.title) == ["Hide Projects", "Hide Sessions", "Move Focus to Next Pane", "Move Focus to Previous Pane", "", "Make Text Bigger", "Make Text Smaller", "Reset Text Size"])
        #expect(try items("Edit").map(\.title) == ["Undo", "Redo", "", "Cut", "Copy", "Paste", "Select All", "", "Find"])
        #expect(try items("Edit").prefix(7).map(key) == ["z", "shift-z", "", "x", "c", "v", "a"])
        let find = try #require(try items("Edit").last?.submenu).items
        #expect(find.map(\.title) == ["Find…", "Find Next", "Find Previous", "Use Selection for Find"])
        #expect(find.map(key) == ["f", "g", "shift-g", "e"] && find.map(\.tag) == [1, 2, 3, 7])
        #expect(find.allSatisfy { $0.action == Selector(("performFindPanelAction:")) && $0.target == nil })
        // This application has a nondefault socket and no setup of its own, so
        // the item is off. Do not send its action: it would register the real launch agent.
        #expect(!application.validateMenuItem(file[8]))

        // Each session command is on only when it can act.
        #expect(!workspace.validateMenuItem(file[0]) && !workspace.validateMenuItem(file[1]) && !workspace.validateMenuItem(file[4]) && !workspace.validateMenuItem(session[2]))
        workspace.showsSessionAtStart = false
        application.applicationDidFinishLaunching(launch)
        let shell = try test.createShell()
        #expect(await waitUntil { test.shownRows == [shell] })
        #expect(workspace.validateMenuItem(file[0]) && workspace.validateMenuItem(file[1]) && !workspace.validateMenuItem(file[4]) && !workspace.validateMenuItem(session[0]))
        workspace.select(row: shell)
        #expect(workspace.validateMenuItem(file[4]) && workspace.validateMenuItem(session[0]) && workspace.validateMenuItem(session[2]))
        let commands = try #require(file[2].submenu)
        workspace.menuNeedsUpdate(commands)
        #expect(commands.items.map(\.title) == ["Claude Code", "Codex"] && commands.items.allSatisfy { $0.target === workspace })
    }

    @Test func theStandardNewSessionUsesTheHomeFolder() {
        guard case .newSession(let folder, let environment) = SessionStart.newSessionInHomeFolder() else {
            Issue.record("Expected a new session")
            return
        }
        #expect(folder == NSHomeDirectory())
        #expect(environment["PATH"] == ProcessInfo.processInfo.environment["PATH"])
    }
}
