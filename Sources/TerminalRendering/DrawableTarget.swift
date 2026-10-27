import Metal
import QuartzCore

/// The drawable of a window layer, as a place to draw. The renderer presents
/// it when its commands are ready.
public struct DrawableTarget: RenderTarget {
    private let drawable: CAMetalDrawable

    public init(_ drawable: CAMetalDrawable) {
        self.drawable = drawable
    }

    public var texture: MTLTexture { drawable.texture }

    public func present(with commandBuffer: MTLCommandBuffer) {
        commandBuffer.present(drawable)
    }
}
