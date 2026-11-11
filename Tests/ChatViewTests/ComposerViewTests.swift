import AppKit
import Testing

@testable import ChatView

@MainActor struct ComposerViewTests {
    let composer = ComposerView(palette: ChatPalette(appearance: .graphite))

    @Test func theFieldGrowsWithItsText() {
        composer.noteButton.isHidden = true
        composer.textView.font = composer.palette.bodyFont
        let empty = composer.height(forWidth: 600)
        composer.textView.string = "One\nTwo\nThree"
        #expect(composer.height(forWidth: 600) > empty + 30)
        composer.frame = NSRect(x: 0, y: 0, width: 600, height: composer.height(forWidth: 600))
        composer.layout()
        #expect(composer.scrollView.frame.height == composer.composerLayout(forWidth: 600).field.height)
    }
}
