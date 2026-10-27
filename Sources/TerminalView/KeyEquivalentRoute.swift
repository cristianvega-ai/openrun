import AppKit

/// What a view does with a key equivalent. AppKit offers each key that
/// could be a shortcut to the views through `performKeyEquivalent`, before
/// the key reaches `keyDown`.
enum KeyEquivalentRoute: Equatable {
    /// AppKit goes on with the key: the menu, and then `keyDown`.
    case appKit
    /// The view sends the key to `keyDown`, one time, and tells AppKit that it took the key.
    case keyDown
    /// The menu gets the key first. When no menu item takes it, the view runs the
    /// action of the key if the key has one, and sends it to `keyDown` if not.
    case menuFirst(fallback: Selector?)

    /// - Parameter hasMarkedText: An input method holds marked text. Then the key must
    ///   go through `interpretKeyEvents` one time only, and the view gives it back to AppKit.
    static func route(for event: NSEvent, hasMarkedText: Bool) -> KeyEquivalentRoute {
        guard event.type == .keyDown, !hasMarkedText else { return .appKit }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags.contains(.command) { return .menuFirst(fallback: fallback(for: event.charactersIgnoringModifiers, flags: flags)) }
        // Control-Return opens a context menu and Control-slash makes a beep,
        // unless the view takes them. A program wants all Control keys.
        return flags.contains(.control) ? .keyDown : .appKit
    }

    /// The keys that the view handles itself when no menu item has them.
    private static func fallback(for characters: String?, flags: NSEvent.ModifierFlags) -> Selector? {
        switch (characters, flags) {
        case ("+", .command), ("=", .command), ("+", [.command, .shift]), ("=", [.command, .shift]):
            #selector(TerminalView.increaseFontSize(_:))
        case ("-", .command): #selector(TerminalView.decreaseFontSize(_:))
        case ("0", .command): #selector(TerminalView.resetFontSize(_:))
        default: nil
        }
    }
}
