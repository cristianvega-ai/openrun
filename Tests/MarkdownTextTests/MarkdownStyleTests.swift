import AppKit
import Testing
@testable import MarkdownText

struct MarkdownStyleTests {
    let style = MarkdownTestStyle.standard

    @Test func inlineStylesDeriveFromTheBodyFont() {
        let body = style.bodyFont
        #expect(style.font(for: .bold, base: body).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(style.font(for: .italic, base: body).fontDescriptor.symbolicTraits.contains(.italic))
        let code = style.font(for: [.code, .bold], base: body)
        #expect(code.isFixedPitch)
        #expect(code.pointSize == 13)
        #expect(code.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func headingsGetSmallerWithTheirLevel() {
        let sizes = (1...6).map { style.headingFont(level: $0).pointSize }
        #expect(sizes == [20, 17, 15, 14, 14, 14])
        #expect(style.headingFont(level: 1).fontDescriptor.symbolicTraits.contains(.bold))
    }
}
