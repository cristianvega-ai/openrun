import AppKit
import Testing
@testable import ChatView

@MainActor struct ChatPaletteTests {
    let palette = ChatPalette(appearance: .graphite)

    private func resolved(_ color: NSColor, in name: NSAppearance.Name) -> NSColor? {
        var result: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) }
        return result
    }

    @Test func colorsFollowTheAppearanceThatTheyDrawIn() throws {
        let light = try #require(resolved(palette.background, in: .aqua))
        let dark = try #require(resolved(palette.background, in: .darkAqua))
        #expect(abs(light.redComponent - 250 / 255) < 0.002)
        #expect(abs(dark.redComponent - 30 / 255) < 0.002)
    }

    @Test func attentionKeepsItsHueInBothAppearances() throws {
        let light = try #require(resolved(palette.attention, in: .aqua))
        let dark = try #require(resolved(palette.attention, in: .darkAqua))
        #expect(light.redComponent > light.blueComponent && dark.redComponent > dark.blueComponent)
        #expect(dark.redComponent > light.redComponent)
    }

    @Test func fontsFollowTheSizesOfTheAppearance() {
        var appearance = ChatAppearance.graphite
        appearance.bodyFontSize = 16
        appearance.codeFontSize = 13
        let palette = ChatPalette(appearance: appearance)
        #expect(palette.bodyFont.pointSize == 16)
        #expect(palette.codeFont.pointSize == 13)
        #expect(palette.codeFont.isFixedPitch)
        #expect(palette.markdownStyle.bodyFont == palette.bodyFont)
    }
}
