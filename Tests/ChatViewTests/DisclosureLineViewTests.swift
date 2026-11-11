import AppKit
import Testing

@testable import ChatView

@MainActor struct DisclosureLineViewTests {
    @Test func aPressRunsTheActionAndVoiceOverHearsTheState() {
        let line = DisclosureLineView()
        var presses = 0
        line.action = { presses += 1 }
        line.show(symbolName: "terminal", title: "Ran swift test", status: "Exit code 1", palette: ChatPalette(appearance: .graphite))
        #expect(line.accessibilityPerformPress())
        #expect(presses == 1)
        #expect(line.accessibilityLabel() == "Ran swift test, Exit code 1")
        #expect(line.acceptsFirstResponder)
    }

    @Test func theLineWithTheKeyboardFocusShowsAMark() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let line = DisclosureLineView(frame: NSRect(x: 0, y: 0, width: 300, height: DisclosureLineView.height))
        line.action = {}
        window.contentView?.addSubview(line)
        #expect(!line.showsFocusMark)
        window.makeFirstResponder(line)
        #expect(line.showsFocusMark)
        window.makeFirstResponder(nil)
        #expect(!line.showsFocusMark)
    }
}
