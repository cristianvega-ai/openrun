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
