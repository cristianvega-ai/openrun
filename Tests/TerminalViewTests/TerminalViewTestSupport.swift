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
