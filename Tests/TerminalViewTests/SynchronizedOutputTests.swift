import Metal
import TerminalEmulation
import TerminalRendering
import Testing
@testable import TerminalView

@MainActor @Suite struct SynchronizedOutputTests {
    /// A view with a full block in its first cell, and the clock that it uses.
    private func makeView() throws -> (view: TerminalView, clock: ManualClock, target: OffscreenTarget) {
        let clock = ManualClock()
        let view = try TerminalView(clock: clock)
        view.terminal.write("\u{1B}[?25l█")
        let size = view.renderer.pixelSize(for: view.gridSize)
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: size.width, height: size.height)
        try view.drawFrame(into: target)
        return (view, clock, target)
    }

    /// Draws a frame and tells if the first cell shows the block.
    private func showsBlock(_ view: TerminalView, _ target: OffscreenTarget) throws -> Bool {
        try view.drawFrame(into: target)
        let fonts = view.renderer.fonts, padding = view.renderer.padding
        return target.pixel(horizontalPosition: padding + fonts.cellWidth / 2, verticalPosition: padding + fonts.cellHeight / 2) == view.theme.foreground
    }

    @Test func theViewKeepsTheFrameOfTheHoldUntilTheProgramLetsGo() throws {
        let (view, _, target) = try makeView()
        view.terminal.write("\u{1B}[?2026h\u{1B}[2J\u{1B}[H")
        #expect(try showsBlock(view, target))
        view.terminal.write("\u{1B}[6Gmore output")
        #expect(try showsBlock(view, target))
        view.terminal.write("\u{1B}[?2026l")
        #expect(try !showsBlock(view, target))
    }

    @Test func aHoldEndsAfterOneSecondAndTheModeOfTheProgramEnds() throws {
        let (view, clock, target) = try makeView()
        view.terminal.write("\u{1B}[?2026h\u{1B}[2J\u{1B}[H")
        clock.advance(by: .milliseconds(999))
        #expect(try showsBlock(view, target) && view.terminal.isModeEnabled(.synchronizedOutput))
        clock.advance(by: .milliseconds(1))
        #expect(!view.terminal.isModeEnabled(.synchronizedOutput))
        #expect(try !showsBlock(view, target))
    }
}
