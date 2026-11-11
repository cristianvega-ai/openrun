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
}
