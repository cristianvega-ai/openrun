import AppKit
import Metal
import TerminalRendering
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

@MainActor @Suite struct DisplayScheduleTests {
    @Test(.enabled(if: NSScreen.main != nil))
    func aRequestGivesOneFrameAndThenTheLinkWaits() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var frames = 0
        let schedule = DisplaySchedule(view: view) { frames += 1 }
        let window = show(view)
        defer { schedule.stop(); window.close() }
        schedule.requestFrame()
        wait(seconds: 3) { frames > 0 }
        wait(seconds: 0.3) { false }
        #expect(frames == 1)
        schedule.requestFrame()
        wait(seconds: 3) { frames > 1 }
        #expect(frames == 2)
    }

    @Test func aRequestWithoutAWindowWaitsForTheWindow() {
        var frames = 0
        let schedule = DisplaySchedule(view: NSView()) { frames += 1 }
        schedule.requestFrame()
        wait(seconds: 0.2) { frames > 0 }
        #expect(frames == 0)
    }
}

@MainActor @Suite struct TerminalViewTests {
    @Test func outputAppearsInTheColorsOfTheTheme() throws {
        let view = try TerminalView()
        view.write(Array("\u{1B}[?25l█".utf8))
        let fonts = view.renderer.fonts
        let size = view.renderer.pixelSize(for: view.terminal.size)
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: size.width, height: size.height)
        try view.drawFrame(into: target)
        #expect(target.pixel(x: view.renderer.padding + fonts.cellWidth / 2, y: view.renderer.padding + fonts.cellHeight / 2) == view.theme.foreground)
        #expect(target.pixel(x: size.width - 1, y: size.height - 1) == view.theme.background)
    }
}
