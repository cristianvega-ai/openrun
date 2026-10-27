import Metal
import Testing
@testable import TerminalView

@MainActor @Suite struct MetalLayerHostTests {
    @Test func theDrawableHasOnePixelForEachPixelOfTheScreen() throws {
        let host = MetalLayerHost(device: try #require(MTLCreateSystemDefaultDevice()))
        host.resize(to: CGSize(width: 100.4, height: 50), scale: 2)
        #expect(host.layer.drawableSize == CGSize(width: 201, height: 100))
        #expect(host.layer.contentsScale == 2)
        #expect(host.layer.pixelFormat == .bgra8Unorm)
        #expect(host.nextTarget()?.texture.width == 201)
    }
}
