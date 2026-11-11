import AppKit
import Testing

@testable import ChatView

@MainActor struct RowSymbolTests {
    @Test func aSymbolButtonHasALabelForVoiceOver() {
        let button = RowSymbol.button("doc.on.doc", label: "Copy Code", target: nil, action: #selector(NSText.copy(_:)))
        #expect(button.image != nil)
        #expect(!button.isBordered)
        #expect(button.accessibilityLabel() == "Copy Code")
    }

    @Test func aSidewaysScrollViewHasNoVerticalScroller() {
        let scrollView = SidewaysScrollView(frame: .zero)
        #expect(scrollView.hasHorizontalScroller)
        #expect(!scrollView.hasVerticalScroller)
    }
}
