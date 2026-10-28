import Metal

/// Compiles the shaders and builds the two pipelines of the renderer: one for
/// rectangles and one for glyphs.
struct ShaderLibrary {
    let rectangles: MTLRenderPipelineState
    let glyphs: MTLRenderPipelineState
    /// How long the compile took. The first compile on a Mac is the slowest.
    let compileTime: Duration

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, source: String = ShaderSource.text) throws {
        let start = ContinuousClock.now
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RenderingError.shaderCompilationFailed("\(error)")
        }
        compileTime = start.duration(to: .now)
        func pipeline(fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "quadrilateralVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            // The fragment functions give colors that are multiplied by their alpha.
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        rectangles = try pipeline(fragment: "rectangleFragment")
        glyphs = try pipeline(fragment: "glyphFragment")
    }
}
