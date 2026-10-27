import Metal
import QuartzCore
import TerminalRendering

/// The layer that holds the pixels of a terminal view.
@MainActor
final class MetalLayerHost {
    let layer = CAMetalLayer()

    init(device: MTLDevice) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        // The colors of the theme are sRGB values. A layer tagged with sRGB
        // shows them with no change.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = true
    }

    /// Gives the drawable one pixel for each pixel of the screen.
    func resize(to size: CGSize, scale: CGFloat) {
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// The place to draw the next frame, or `nil` when the layer has no drawable now.
    func nextTarget() -> DrawableTarget? {
        layer.nextDrawable().map(DrawableTarget.init)
    }
}
