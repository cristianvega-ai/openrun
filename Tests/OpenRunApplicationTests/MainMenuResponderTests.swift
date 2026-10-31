import AppKit
import SessionProcessHarness
import SessionProtocol
@testable import SessionWindow
import TerminalView
import XCTest
@testable import OpenRunApplication

final class MainMenuResponderTests: XCTestCase {
    @MainActor func testTheFontShortcutsUseTheInstalledMenuAndFocusedResponder() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENRUN_INTERACTIVE_MENU_TEST"] == "1",
            "Set OPENRUN_INTERACTIVE_MENU_TEST=1 in an interactive session; this test activates its window.")

        let app = NSApplication.shared
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let oldPolicy = app.activationPolicy()
        let oldMenu = app.mainMenu, oldWindows = app.windowsMenu
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zshrc").path, contents: Data())
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let application = OpenRunApplication(socket: try SocketLocation(path: process.socketPath))
        application.makeNewSession = { .newSession(folder: folder.path, environment: ["HOME": folder.path, "ZDOTDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            app.mainMenu = oldMenu
            app.windowsMenu = oldWindows
            if app.isActive, previousApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication?.activate()
            }
            _ = app.setActivationPolicy(oldPolicy)
        }
        try XCTSkipUnless(app.setActivationPolicy(.regular), "The test host cannot use the regular activation policy.")
        let menu = MainMenu.make(target: application)
        app.mainMenu = menu
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await wait { application.windows.controllers.first?.view != nil }
        let controller = try XCTUnwrap(application.windows.controllers.first)
        let view = try XCTUnwrap(controller.view)
        await wait { app.isActive && app.keyWindow === controller.window && controller.window.isKeyWindow }
        try XCTSkipUnless(app.isActive && app.keyWindow === controller.window && controller.window.isKeyWindow,
            "The test host did not become active with its OpenRun window key; AppKit cannot resolve its first responder.")
        XCTAssertTrue(controller.window.firstResponder === view)
        let textMenu = try XCTUnwrap(menu.item(withTitle: "View")?.submenu)
        for title in ["Make Text Bigger", "Make Text Smaller", "Reset Text Size"] {
            let item = try XCTUnwrap(textMenu.item(withTitle: title))
            let action = try XCTUnwrap(item.action)
            XCTAssertNil(item.target)
            XCTAssertTrue((app.target(forAction: action, to: nil, from: item) as AnyObject?) === view)
        }

        let first = view.gridSize
        XCTAssertTrue(menu.performKeyEquivalent(with: try key("=", .command, in: controller.window, code: 24)))
        await wait { view.gridSize.columns < first.columns }
        let second = view.gridSize
        XCTAssertLessThan(second.columns, first.columns)
        XCTAssertTrue(view.performKeyEquivalent(with: try key("+", [.command, .shift], in: controller.window, code: 24)))
        await wait { view.gridSize.columns < second.columns }
        XCTAssertLessThan(view.gridSize.columns, second.columns)
        XCTAssertTrue(menu.performKeyEquivalent(with: try key("-", .command, in: controller.window, code: 27)))
        await wait { view.gridSize == second }
        XCTAssertEqual(view.gridSize, second)
        XCTAssertTrue(menu.performKeyEquivalent(with: try key("0", .command, in: controller.window, code: 29)))
        await wait { view.gridSize == first }
        XCTAssertEqual(view.gridSize, first)
        let otherView = try TerminalView()
        otherView.frame = view.frame
        let content = try XCTUnwrap(controller.window.contentView)
        content.addSubview(otherView)
        defer { otherView.removeFromSuperview() }
        otherView.layoutSubtreeIfNeeded()
        let otherFirst = otherView.gridSize
        XCTAssertTrue(controller.window.makeFirstResponder(otherView))
        let bigger = try XCTUnwrap(textMenu.item(withTitle: "Make Text Bigger"))
        XCTAssertTrue((app.target(forAction: try XCTUnwrap(bigger.action), to: nil, from: bigger) as AnyObject?) === otherView)
        XCTAssertTrue(menu.performKeyEquivalent(with: try key("=", .command, in: controller.window, code: 24)))
        await wait { otherView.gridSize.columns < otherFirst.columns }
        XCTAssertLessThan(otherView.gridSize.columns, otherFirst.columns)
        XCTAssertEqual(view.gridSize, first)
    }

    @MainActor private func key(_ characters: String, _ flags: NSEvent.ModifierFlags, in window: NSWindow, code: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @MainActor private func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            runLoopTurn()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor private func runLoopTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
}
