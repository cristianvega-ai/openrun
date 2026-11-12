// Draws the icon of OpenRun.app and writes it as an icns file.
// Usage: swift scripts/make-application-icon.swift OUTPUT.icns
//
// The icon is a prompt on the Graphite background: the sign of a shell
// prompt in the text color, and the cursor in the one accent of the theme.
import AppKit

/// One picture of the icon with `pixels` on each side.
func picture(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    let unit = CGFloat(pixels) / 1024
    context.scaleBy(x: unit, y: unit)

    func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    // The shape of a Mac icon: 824 points of 1024, with round corners and a soft shadow.
    let shape = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(color(0x1E2022))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x34383B), color(0x1E2022)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    context.restoreGState()

    // The sign of the prompt.
    context.setStrokeColor(color(0xE6EEF4))
    context.setLineWidth(76)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 318, y: 668))
    context.addLine(to: CGPoint(x: 492, y: 512))
    context.addLine(to: CGPoint(x: 318, y: 356))
    context.strokePath()
    // The cursor, in the attention color of Graphite.
    context.addPath(CGPath(roundedRect: CGRect(x: 560, y: 330, width: 170, height: 76), cornerWidth: 26, cornerHeight: 26, transform: nil))
    context.setFillColor(color(0xF08F9B))
    context.fillPath()
    NSGraphicsContext.current = nil
    return bitmap.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/make-application-icon.swift OUTPUT.icns\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = FileManager.default.temporaryDirectory.appending(path: "OpenRun-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
// The names that iconutil reads: each size once, and once at two times the pixels.
for points in [16, 32, 128, 256, 512] {
    try picture(pixels: points).write(to: folder.appending(path: "icon_\(points)x\(points).png"))
    try picture(pixels: points * 2).write(to: folder.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["--convert", "icns", "--output", output.path, folder.path]
try tool.run()
tool.waitUntilExit()
exit(tool.terminationStatus)
