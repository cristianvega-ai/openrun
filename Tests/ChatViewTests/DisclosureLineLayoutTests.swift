import AppKit
import Testing

@testable import ChatView

@MainActor struct DisclosureLineLayoutTests {
    @Test func aLongStateGivesWayToTheTitle() {
        let line = DisclosureLineView(frame: NSRect(x: 0, y: 0, width: 320, height: DisclosureLineView.height))
        line.show(symbolName: "hand.raised", title: "Denied: rm -rf .build", status: String(repeating: "A long message. ", count: 10),
                  palette: ChatPalette(appearance: .graphite))
        line.layout()
        #expect(line.title.frame.width > 100)
        #expect(line.status.frame.maxX <= 320)
    }
}
