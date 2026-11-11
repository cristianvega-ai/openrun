import AppKit
import Testing

@testable import ChatView

@MainActor struct ChatTextViewTests {
    @Test func theColumnStandsInTheMiddleOfAWidePane() {
        #expect(ChatColumn.frame(inWidth: 1000) == (140, ChatColumn.maximumWidth))
        #expect(ChatColumn.frame(inWidth: 360) == (ChatColumn.minimumMargin, 320))
    }

    @Test func textGrowsTallerWhenItWrapsAtLessWidth() {
        let view = ChatTextView()
        view.show(NSAttributedString(string: String(repeating: "word ", count: 80), attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        let wide = view.fittingHeight(forWidth: 600)
        let narrow = view.fittingHeight(forWidth: 200)
        #expect(wide > 0)
        #expect(narrow > wide * 2)
    }

    @Test func aClickOnALinkGoesOnlyToTheAction() {
        let view = ChatTextView()
        var opened: [String] = []
        view.linkAction = { opened.append($0) }
        #expect(view.textView(view, clickedOnLink: "https://example.com", at: 0))
        #expect(opened == ["https://example.com"])
    }
}
