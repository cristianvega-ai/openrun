import AppKit
import SessionProtocol
@testable import SessionPane
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct MainMenuTests {
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
}
