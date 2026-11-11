import AppKit

/// The menu of a right click: the link under the pointer, copy, paste and
/// select all (decision of 2026-11-10). A program that asked for mouse reports
/// gets the right click instead, unless Shift is down, as for a selection.
extension TerminalView {
    public override func menu(for event: NSEvent) -> NSMenu? {
        guard !pointer.reporter.isActive || event.modifierFlags.contains(.shift) else { return nil }
        let menu = NSMenu(title: "Terminal")
        let cell = pointerLocation.cell(of: convert(event.locationInWindow, from: nil))
        if let address = links.address(at: cell), LinkSchemeRule.target(for: address) != nil {
            menu.addItem(item("Open Link", #selector(openLinkFromMenu(_:)), address))
            menu.addItem(item("Copy Link", #selector(copyLinkFromMenu(_:)), address))
            menu.addItem(.separator())
        }
        if terminal.hasSelection { menu.addItem(item("Copy", #selector(copy(_:)))) }
        menu.addItem(item("Paste", #selector(paste(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(selectAll(_:))))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ address: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = address
        return item
    }

    @objc func openLinkFromMenu(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        links.open(address)
    }

    @objc func copyLinkFromMenu(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        pasteboard.write(plainText: address)
    }
}
