import AppKit

/// The menu can offer copy only for a selection and paste only for text.
extension TerminalView: NSMenuItemValidation {
    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)):
            return terminal.hasSelection
        case #selector(paste(_:)):
            return pasteboard.hasPlainText
        default:
            return true
        }
    }
}
