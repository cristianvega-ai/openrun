import CoreGraphics
import Testing

@testable import ChatView

@MainActor struct ComposerLayoutTests {
    @Test func theFieldGrowsUpToTheLimitAndThenStays() {
        let one = ComposerLayout(width: 600, textHeight: 0, lineHeight: 18, hasNote: false, hasImages: false)
        let three = ComposerLayout(width: 600, textHeight: 54, lineHeight: 18, hasNote: false, hasImages: false)
        let many = ComposerLayout(width: 600, textHeight: 900, lineHeight: 18, hasNote: false, hasImages: false)
        #expect(one.field.height == 18)
        #expect(three.height == one.height + 36)
        #expect(many.field.height == ComposerLayout.maximumFieldHeight)
    }

    @Test func aNoteAndImagesTakeTheirOwnSpace() {
        let plain = ComposerLayout(width: 360, textHeight: 18, lineHeight: 18, hasNote: false, hasImages: false)
        let full = ComposerLayout(width: 360, textHeight: 18, lineHeight: 18, hasNote: true, hasImages: true)
        #expect(full.height == plain.height + ComposerLayout.noteHeight + ImagePreviewsView.height + 8)
        #expect(full.field.minY > (full.previews?.maxY ?? 0))
        #expect(full.box.maxX <= 360 - ChatColumn.minimumMargin)
    }
}
