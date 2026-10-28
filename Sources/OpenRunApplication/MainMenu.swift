import AppKit

/// The menu of the app. Window actions go through the responder chain to the
/// view that has focus.
@MainActor
enum MainMenu {
    static func make(target: OpenRunApplication) -> NSMenu {
        let menu = NSMenu()
        let application = submenu("OpenRun", in: menu)
        application.addItem(item("About OpenRun", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        application.addItem(.separator())
        application.addItem(item("Hide OpenRun", #selector(NSApplication.hide(_:)), "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        application.addItem(hideOthers)
        application.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        application.addItem(.separator())
        application.addItem(item("Quit OpenRun", #selector(NSApplication.terminate(_:)), "q"))

        let file = submenu("File", in: menu)
        let newSession = item("New Window", #selector(OpenRunApplication.newSession(_:)), "n")
        let attach = item("Attach to Session…", #selector(OpenRunApplication.attachToSession(_:)))
        newSession.target = target
        attach.target = target
        file.addItem(newSession)
        file.addItem(attach)
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))

        let edit = submenu("Edit", in: menu)
        edit.addItem(item("Copy", Selector(("copy:")), "c"))
        edit.addItem(item("Paste", Selector(("paste:")), "v"))
        let view = submenu("View", in: menu)
        view.addItem(item("Make Text Bigger", Selector(("increaseFontSize:")), "="))
        view.addItem(item("Make Text Smaller", Selector(("decreaseFontSize:")), "-"))
        view.addItem(item("Reset Text Size", Selector(("resetFontSize:")), "0"))
        let windows = submenu("Window", in: menu)
        windows.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windows.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        windows.addItem(.separator())
        windows.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = windows
        return menu
    }

    private static func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(title: title)
        item.submenu = child
        menu.addItem(item)
        return child
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
