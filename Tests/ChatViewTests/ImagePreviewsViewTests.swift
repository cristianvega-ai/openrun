import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct ImagePreviewsViewTests {
    @Test func eachPreviewHasARemoveButton() {
        let view = ImagePreviewsView()
        let image = MessageImage(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        view.show([image, image], palette: ChatPalette(appearance: .graphite))
        #expect(view.previews.count == 2)
        var removed: [Int] = []
        view.removeAction = { removed.append($0) }
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        buttons.last?.performClick(nil)
        #expect(removed == [1])
        #expect(buttons.last?.accessibilityLabel() == "Remove Image 2")
    }
}
