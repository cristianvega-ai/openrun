import Metal
import TerminalEmulation
import TerminalRendering
import Testing
@testable import TerminalView

@MainActor @Suite struct BellFlashTests {
    private func makeView() throws -> (view: TerminalView, clock: ManualClock, target: OffscreenTarget) {
        let clock = ManualClock()
        let view = try TerminalView(clock: clock)
        let size = view.renderer.pixelSize(for: view.gridSize)
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: size.width, height: size.height)
        return (view, clock, target)
    }

    /// Draws a frame and tells if the corner of the picture has the flash.
    private func isFlashing(_ view: TerminalView, _ target: OffscreenTarget) throws -> Bool {
        try view.drawFrame(into: target)
        return target.pixel(horizontalPosition: 0, verticalPosition: 0) != view.theme.background
    }

    @Test func theBellFlashesTheViewFor150MillisecondsWithoutASound() throws {
        let (view, clock, target) = try makeView()
        #expect(try !isFlashing(view, target))
        view.terminal.write("\u{07}")
        #expect(try isFlashing(view, target))
        clock.advance(by: .milliseconds(149))
        #expect(try isFlashing(view, target))
        clock.advance(by: .milliseconds(1))
        #expect(try !isFlashing(view, target))
    }

    @Test func aSecondBellDuringAFlashMakesItLonger() throws {
        let (view, clock, target) = try makeView()
        view.terminal.write("\u{07}")
        clock.advance(by: .milliseconds(100))
        view.terminal.write("\u{07}")
        clock.advance(by: .milliseconds(100))
        #expect(try isFlashing(view, target))
        clock.advance(by: .milliseconds(50))
        #expect(try !isFlashing(view, target))
    }
}
