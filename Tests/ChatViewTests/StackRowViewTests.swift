import AppKit
import Testing

@testable import ChatView

@MainActor struct StackRowViewTests {
    @Test func partsStandOneAboveTheOther() {
        let view = StackRowView()
        let line = DisclosureLineView()
        let box = DetailBoxView()
        box.show([("output", nil)], palette: ChatPalette(appearance: .graphite))
        view.setParts([StackRowView.Part(view: line), StackRowView.Part(view: box, indentation: 24)])
        view.frame = NSRect(x: 0, y: 0, width: 600, height: view.height(forWidth: 600))
        view.layout()
        #expect(line.frame.minX == ChatColumn.frame(inWidth: 600).x - 6)
        #expect(box.frame.minX == ChatColumn.frame(inWidth: 600).x + 24)
        #expect(box.frame.minY > line.frame.maxY)
        view.setParts([StackRowView.Part(view: line)])
        #expect(box.superview == nil)
    }
}
