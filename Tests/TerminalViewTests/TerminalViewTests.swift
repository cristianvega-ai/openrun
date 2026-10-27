import AppKit
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
