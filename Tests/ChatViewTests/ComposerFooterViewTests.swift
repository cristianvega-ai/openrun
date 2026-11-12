import AppKit
import Testing

@testable import ChatView

@MainActor struct ComposerFooterViewTests {
    @Test func theFooterShowsTheFacts() {
        let footer = ComposerFooterView()
        let opus = ChatChoice(identifier: "opus", title: "Opus 5.5")
        let sonnet = ChatChoice(identifier: "sonnet", title: "Sonnet 5.5")
        footer.show(ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Claude Code", model: opus, models: [opus, sonnet],
                                    folder: "~/Projects/openrun", branch: "main", usage: "Week 37% used · read 14:32"), palette: ChatPalette(appearance: .graphite))
        #expect(footer.modelButton.title == "Opus 5.5")
        #expect(footer.modeButton.isHidden)
        #expect(footer.placeLabel.stringValue.contains("main") && footer.placeLabel.stringValue.hasSuffix("Week 37% used · read 14:32"))
        let style = footer.placeLabel.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byTruncatingMiddle)
    }
}
