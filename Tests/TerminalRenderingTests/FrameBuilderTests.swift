import Testing
@testable import TerminalRendering

@Suite struct FrameBuilderTests {
    @Test func theCellLayoutMatchesTheShader() {
        #expect(MemoryLayout<CellQuad>.stride == 48)
        #expect(MemoryLayout<CellQuad>.offset(of: \.atlasOrigin) == 16)
        #expect(MemoryLayout<CellQuad>.offset(of: \.color) == 32)
    }
}
