import AppKit
import Testing
@testable import PaneAppearance

@MainActor @Suite struct PaneBackgroundViewTests {
    /// Draws the view in an appearance, into an image twice its height.
    private func draw(_ view: PaneBackgroundView, in appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            view.draw(NSRect(x: 0, y: 0, width: 20, height: 40))
        }
        NSGraphicsContext.restoreGraphicsState()
        return image
    }

    /// The pane color follows the appearance, and the view paints only its own bounds.
    @Test func theViewPaintsItsPaneColorForTheAppearance() throws {
        let view = PaneBackgroundView(color: PaneColor.firstPane)
        view.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        let light = try draw(view, in: .aqua), dark = try draw(view, in: .darkAqua)
        #expect((light.colorAt(x: 10, y: 30)?.brightnessComponent ?? 0) > 0.8)
        #expect((dark.colorAt(x: 10, y: 30)?.brightnessComponent ?? 1) < 0.25)
        #expect(light.colorAt(x: 10, y: 10)?.alphaComponent == 0 && view.isOpaque)
    }
}
