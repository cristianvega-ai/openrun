import AppKit

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
    func make(_ characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: all, timestamp: timestamp, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode))!
    }
    return type == .flagsChanged ? make("") : make(make("").characters(byApplyingModifiers: all) ?? "")
}

/// The tests of keys assume the US layout of the keyboard, as the Macs of the owner have.
let usLayoutIsCurrent = keyEvent(5, .option).characters(byApplyingModifiers: .option) == "©"
