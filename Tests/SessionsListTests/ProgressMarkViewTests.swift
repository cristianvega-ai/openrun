import AppKit
import Testing
@testable import SessionsList

@MainActor @Suite struct ProgressMarkViewTests {
    @Test func theMarkTurnsOnlyInAWindowWhileVisibleAndWithoutReduceMotion() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let mark = ProgressMarkView()
        var reducesMotion = false
        mark.reducesMotion = { reducesMotion }
        #expect(!mark.isTurning)
        window.contentView?.addSubview(mark)
        #expect(mark.isTurning)
        mark.isHidden = true
        #expect(!mark.isTurning)
        mark.isHidden = false
        #expect(mark.isTurning)
        reducesMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        #expect(!mark.isTurning)
        mark.removeFromSuperview()
        #expect(!mark.isTurning)
    }
}
