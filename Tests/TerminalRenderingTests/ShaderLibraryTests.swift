import Metal
import Testing
@testable import TerminalRendering

@Suite struct ShaderLibraryTests {
    @Test func theShadersCompileFromSwiftSourceAndMakeTwoPipelines() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try ShaderLibrary(device: device, pixelFormat: .bgra8Unorm)
        #expect(library.rectangles !== library.glyphs)
        print("shader compile time: \(library.compileTime)")
    }

    @Test func brokenSourceThrowsTheMessageOfMetal() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        #expect(throws: RenderingError.self) {
            try ShaderLibrary(device: device, pixelFormat: .bgra8Unorm, source: "vertex nonsense")
        }
    }
}
