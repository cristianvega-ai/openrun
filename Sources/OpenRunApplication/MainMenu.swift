import AppKit

/// The menu of the app. The session commands go to the host of the main
/// window, and the text commands go through the responder chain to the
/// view that has the focus.
@MainActor
enum MainMenu {
    static func make(target: OpenRunApplication) -> NSMenu {
        let menu = NSMenu()
        let application = submenu("OpenRun", in: menu)
        application.addItem(item("About OpenRun", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        application.addItem(.separator())
        application.addItem(item("Settings…", #selector(Workspace.showSettings(_:)), ",", target: target.workspace))
        application.addItem(item("Install Command-Line Tool…", #selector(Workspace.installCommandLineTool(_:)), target: target.workspace))
        application.addItem(.separator())
        application.addItem(item("Hide OpenRun", #selector(NSApplication.hide(_:)), "h"))
        application.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        application.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        application.addItem(.separator())
        application.addItem(item("Quit OpenRun", #selector(NSApplication.terminate(_:)), "q"))
        addFileMenu(to: menu, target: target)

        // Undo, Redo and Cut are for the text fields, such as the composer of a chat.
        let edit = submenu("Edit", in: menu)
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", Selector(("cut:")), "x"))
        edit.addItem(item("Copy", Selector(("copy:")), "c"))
        edit.addItem(item("Paste", Selector(("paste:")), "v"))
        edit.addItem(item("Select All", Selector(("selectAll:")), "a"))
        edit.addItem(.separator())
        // The view with the focus finds: a terminal or a chat.
        let find = submenu("Find", in: edit)
        for (title, key, modifiers, action) in [
            ("Find…", "f", NSEvent.ModifierFlags.command, NSFindPanelAction.showFindPanel), ("Find Next", "g", .command, .next),
            ("Find Previous", "g", [.command, .shift], .previous), ("Use Selection for Find", "e", .command, .setFindString),
        ] {
            let item = item(title, Selector(("performFindPanelAction:")), key, modifiers)
            item.tag = Int(action.rawValue)
            find.addItem(item)
        }
        let view = submenu("View", in: menu)
        for item in target.workspace.window.paneMenuItems() { view.addItem(item) }
        view.addItem(.separator())
        view.addItem(item("Make Text Bigger", Selector(("increaseFontSize:")), "="))
        view.addItem(item("Make Text Smaller", Selector(("decreaseFontSize:")), "-"))
        view.addItem(item("Reset Text Size", Selector(("resetFontSize:")), "0"))
        addSessionMenu(to: menu, workspace: target.workspace)

        let windows = submenu("Window", in: menu)
        windows.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windows.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        windows.addItem(.separator())
        windows.addItem(item("OpenRun", #selector(Workspace.showMainWindow(_:)), target: target.workspace))
        windows.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = windows
        return menu
    }

    private static func addFileMenu(to menu: NSMenu, target: OpenRunApplication) {
        let file = submenu("File", in: menu), workspace = target.workspace
        file.addItem(item("New Session", #selector(Workspace.newSession(_:)), "n", target: workspace))
        file.addItem(item("New Thread", #selector(Workspace.newThread(_:)), "t", target: workspace))
        let commands = submenu("New Session With", in: file)
        commands.delegate = workspace
        file.addItem(.separator())
        // Command-W ends the work of a row, so the window closes with Shift.
        file.addItem(item("Close Session", #selector(Workspace.closeSession(_:)), "w", target: workspace))
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Retry Session Process", #selector(OpenRunApplication.retrySessionProcess(_:)), target: target))
        file.addItem(item("Register Session Process Again", #selector(OpenRunApplication.registerSessionProcessAgain(_:)), target: target))
    }

    private static func addSessionMenu(to menu: NSMenu, workspace: Workspace) {
        let session = submenu("Session", in: menu)
        session.addItem(item("Rename…", #selector(Workspace.renameSession(_:)), target: workspace))
        session.addItem(item("Clear", #selector(Workspace.clearSession(_:)), "k", target: workspace))
        session.addItem(.separator())
        // A split starts a login shell beside or under the pane with the focus.
        session.addItem(item("Split Right", #selector(Workspace.splitRight(_:)), "d", target: workspace))
        session.addItem(item("Split Down", #selector(Workspace.splitDown(_:)), "d", [.command, .shift], target: workspace))
        session.addItem(item("Split with Browser", #selector(Workspace.splitWithBrowser(_:)), "b", [.command, .option], target: workspace))
        session.addItem(item("Next Pane", #selector(Workspace.selectNextPane(_:)), "]", target: workspace))
        session.addItem(item("Previous Pane", #selector(Workspace.selectPreviousPane(_:)), "[", target: workspace))
        session.addItem(.separator())
        // The keys of the next and the previous tab of other Mac apps.
        session.addItem(item("Next Session", #selector(Workspace.selectNextSession(_:)), "]", [.command, .shift], target: workspace))
        session.addItem(item("Previous Session", #selector(Workspace.selectPreviousSession(_:)), "[", [.command, .shift], target: workspace))
    }

    private static func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(title: title)
        item.submenu = child
        menu.addItem(item)
        return child
    }

    private static func item(
        _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        (item.keyEquivalentModifierMask, item.target) = (modifiers, target)
        return item
    }
}
