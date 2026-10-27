import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct CursorShapeTests {
    private func quads(_ style: CursorStyle) -> CursorQuads {
        CursorQuads(style: style, x: 100, y: 50, width: 32, height: 31, stroke: 2, color: TerminalColor(red: 1, green: 2, blue: 3))
    }

    private func boxes(_ list: [CellQuad]) -> [[Float]] {
        list.map { [$0.origin.x, $0.origin.y, $0.size.x, $0.size.y] }
    }

    @Test func aBlockIsOneRectangleUnderTheGlyphs() {
        #expect(boxes(quads(.block).backgrounds) == [[100, 50, 32, 31]])
        #expect(quads(.block).overlays.isEmpty)
    }

    @Test func aBarAndAnUnderlineAreOneLineOnTopOfTheGlyphs() {
        #expect(boxes(quads(.bar).overlays) == [[100, 50, 4, 31]])
        #expect(boxes(quads(.underline).overlays) == [[100, 77, 32, 4]])
        #expect(quads(.bar).backgrounds.isEmpty)
    }

    @Test func aHollowBlockIsFourLines() {
        let edges = boxes(quads(.hollowBlock).overlays)
        #expect(edges == [[100, 50, 32, 2], [100, 79, 32, 2], [100, 50, 2, 31], [130, 50, 2, 31]])
    }
}
