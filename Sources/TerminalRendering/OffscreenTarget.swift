import CoreGraphics
import ImageIO
import Metal
import TerminalEmulation
import UniformTypeIdentifiers

/// A texture in memory instead of a window. Tests read its pixels, and a
/// screenshot can save it as a PNG file.
public final class OffscreenTarget: RenderTarget {
    public let texture: MTLTexture
    private var lastCommands: MTLCommandBuffer?

    public init(device: MTLDevice, width: Int, height: Int) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Apple silicon shares its memory, so the processor can read the texture.
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderingError.textureUnavailable }
        self.texture = texture
    }

    public func present(with commandBuffer: MTLCommandBuffer) {
        lastCommands = commandBuffer
    }

    /// Keeps existing callers until they use the full position names.
    public func pixel(x horizontalPosition: Int, y verticalPosition: Int) -> TerminalColor {
        pixel(horizontalPosition: horizontalPosition, verticalPosition: verticalPosition)
    }

    /// The color of one pixel, counted from the top left, after the last draw ended.
    public func pixel(horizontalPosition: Int, verticalPosition: Int) -> TerminalColor {
        lastCommands?.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&bytes, bytesPerRow: 4,
                         from: MTLRegionMake2D(horizontalPosition, verticalPosition, 1, 1), mipmapLevel: 0)
        return TerminalColor(red: bytes[2], green: bytes[1], blue: bytes[0])
    }

    /// Saves the picture as a PNG file, with a density of 144 pixels for each
    /// inch, as a Retina screen has.
    public func savePNG(to url: URL) throws {
        lastCommands?.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        guard let image = bytes.withUnsafeMutableBytes({ buffer in
            CGContext(
                data: buffer.baseAddress, width: texture.width, height: texture.height, bitsPerComponent: 8,
                bytesPerRow: texture.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
        }), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderingError.imageFileFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderingError.imageFileFailed }
    }
}
