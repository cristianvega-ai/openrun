import Metal

/// Where the renderer draws: a texture, and what to do with it at the end.
public protocol RenderTarget {
    var texture: MTLTexture { get }
    /// The renderer calls this before it commits its commands. A window
    /// presents its drawable here.
    func present(with commandBuffer: MTLCommandBuffer)
}
