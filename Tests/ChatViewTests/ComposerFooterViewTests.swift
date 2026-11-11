import AppKit
import Testing

@testable import ChatView

@MainActor struct ComposerFooterViewTests {
    @Test func theFooterShowsTheFacts() {
        let footer = ComposerFooterView()
        let opus = ChatChoice(identifier: "opus", title: "Opus 5.5")
        let sonnet = ChatChoice(identifier: "sonnet", title: "Sonnet 5.5")
        footer.show(ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Claude Code", model: opus, models: [opus, sonnet],
                                    folder: "~/Projects/openrun", branch: "main"), palette: ChatPalette(appearance: .graphite))
        #expect(footer.modelButton.title == "Opus 5.5")
        #expect(footer.modeButton.isHidden)
        #expect(footer.placeLabel.stringValue.hasSuffix("main"))
        let style = footer.placeLabel.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byTruncatingMiddle)
    }
}
