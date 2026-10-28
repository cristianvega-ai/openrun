import AppKit
import Carbon.HIToolbox
import Metal
import TerminalRendering
import Testing
@testable import TerminalView

@MainActor @Suite struct CursorBlinkUnitTests {
    private func makeBlink() -> (CursorBlink, ManualClock) {
        let clock = ManualClock()
        return (CursorBlink(clock: clock) { _ in }, clock)
    }

    @Test func aBlinkingCursorIsHiddenAndShownEvery500Milliseconds() {
        let (blink, clock) = makeBlink()
        blink.update(programBlinks: true, windowIsKey: true)
        clock.advance(by: .milliseconds(499))
        #expect(blink.isShown)
        clock.advance(by: .milliseconds(1))
        #expect(!blink.isShown)
        clock.advance(by: .milliseconds(500))
        #expect(blink.isShown)
    }

    @Test func aSteadyCursorAndAWindowThatIsNotKeyDoNotBlink() {
        let (blink, clock) = makeBlink()
        blink.update(programBlinks: false, windowIsKey: true)
        blink.update(programBlinks: true, windowIsKey: false)
        clock.advance(by: .seconds(5))
        #expect(blink.isShown)
        blink.update(programBlinks: true, windowIsKey: true)
        clock.advance(by: .milliseconds(500))
        blink.update(programBlinks: true, windowIsKey: false)
        clock.advance(by: .seconds(5))
        #expect(blink.isShown)
    }

    @Test func aKeyShowsTheCursorForOneSecondBeforeItBlinksAgain() {
        let (blink, clock) = makeBlink()
        blink.update(programBlinks: true, windowIsKey: true)
        clock.advance(by: .milliseconds(500))
        #expect(!blink.isShown)
        blink.keyPressed()
        #expect(blink.isShown)
        clock.advance(by: .milliseconds(999))
        #expect(blink.isShown)
        clock.advance(by: .milliseconds(1))
        #expect(!blink.isShown)
        clock.advance(by: .milliseconds(500))
        #expect(blink.isShown)
    }
}

@MainActor @Suite struct CursorBlinkOfViewTests {
    private func makeView(_ output: String) throws -> (view: TerminalView, clock: ManualClock, target: OffscreenTarget) {
        let clock = ManualClock()
        let view = try TerminalView(clock: clock)
        view.terminal.write(output)
        let size = view.renderer.pixelSize(for: view.gridSize)
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: size.width, height: size.height)
        try view.drawFrame(into: target)
        return (view, clock, target)
    }

    @Test func theViewDrawsTheCursorInItsShownPhaseOnly() throws {
        let (view, clock, target) = try makeView("\u{1B}[1 q")
        let fonts = view.renderer.fonts, padding = view.renderer.padding
        func isCursorDrawn() throws -> Bool {
            try view.drawFrame(into: target)
            return target.pixel(horizontalPosition: padding + fonts.cellWidth / 2, verticalPosition: padding + fonts.cellHeight / 2) == view.theme.cursor
        }
        #expect(try isCursorDrawn())
        clock.advance(by: .milliseconds(500))
        #expect(try !isCursorDrawn())
        clock.advance(by: .milliseconds(500))
        #expect(try isCursorDrawn())
    }

    @Test func aSteadyCursorAndAWindowThatIsNotKeyDoNotBlinkInTheView() throws {
        let (steady, steadyClock, _) = try makeView("\u{1B}[2 q")
        steadyClock.advance(by: .seconds(5))
        let (view, clock, target) = try makeView("\u{1B}[1 q")
        view.renderer.isFocused = false
        try view.drawFrame(into: target)
        clock.advance(by: .seconds(5))
        #expect(steady.renderer.isCursorShown && view.renderer.isCursorShown)
    }

    @Test(.enabled(if: usLayoutIsCurrent))
    func aKeyShowsTheCursorAgainInTheView() throws {
        let (view, clock, _) = try makeView("\u{1B}[1 q")
        clock.advance(by: .milliseconds(500))
        #expect(!view.renderer.isCursorShown)
        view.keyDown(with: keyEvent(kVK_ANSI_A))
        #expect(view.renderer.isCursorShown)
        clock.advance(by: .milliseconds(1000))
        #expect(!view.renderer.isCursorShown)
    }
}
