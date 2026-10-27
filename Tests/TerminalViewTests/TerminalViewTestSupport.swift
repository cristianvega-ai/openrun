import AppKit
import TerminalEmulation
@testable import TerminalView

/// Keeps what a view tells its owner.
@MainActor final class RecordingDelegate: TerminalViewDelegate {
    var sizes: [TerminalSize] = []
    var sent: [UInt8] = []

    func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize) { sizes.append(size) }
    func terminalView(_ view: TerminalView, send bytes: [UInt8]) { sent += bytes }

    /// The bytes that the view sent since the last call, as text.
    func takeSent() -> String {
        defer { sent = [] }
        return String(decoding: sent, as: UTF8.self)
    }
}

/// A window on the screen that holds `view`, as the display link needs one.
@MainActor
func show(_ view: NSView) -> NSWindow {
    // AppKit needs an application object before it makes a window.
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    // Swift owns the window. AppKit must not release it a second time when it closes.
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderFrontRegardless()
    return window
}

/// A window whose first responder is `view`, so that key equivalents reach it.
@MainActor
func showFocused(_ view: NSView) -> NSWindow {
    let window = show(view)
    window.makeFirstResponder(view)
    return window
}

/// Runs the main run loop until `condition` is true or `seconds` have passed.
@MainActor
func wait(seconds: Double, until condition: () -> Bool) {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
}

/// A key event with the characters that the current keyboard layout makes for
/// the key, as the system sends it. `deviceBits` tell the side of a modifier.
func keyEvent(
    _ keyCode: Int, _ flags: NSEvent.ModifierFlags = [], deviceBits: UInt = 0, type: NSEvent.EventType = .keyDown, timestamp: TimeInterval = 1
) -> NSEvent {
    let all = NSEvent.ModifierFlags(rawValue: flags.rawValue | deviceBits)
    func make(_ characters: String, ignoring: String) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: all, timestamp: timestamp, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: UInt16(keyCode))!
    }
    guard type != .flagsChanged else { return make("", ignoring: "") }
    let blank = make("", ignoring: "")
    // Like the system, the second text leaves out all modifiers but Shift.
    return make(blank.characters(byApplyingModifiers: all) ?? "", ignoring: blank.characters(byApplyingModifiers: all.intersection(.shift)) ?? "")
}

/// The tests of keys assume the US layout of the keyboard, as the Macs of the owner have.
let usLayoutIsCurrent = keyEvent(5, .option).characters(byApplyingModifiers: .option) == "©"
