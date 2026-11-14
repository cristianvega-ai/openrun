import AppKit
import Testing
import AccountUsage

@MainActor @Suite struct UsageMeterViewTests {
    @Test func aSmallUseStillShowsAndAFullWindowFillsTheMeter() {
        let meter = UsageMeterView(frame: NSRect(x: 0, y: 0, width: 100, height: 4))
        #expect(meter.filledWidth == 0 && meter.intrinsicContentSize.height == 4)
        meter.fraction = 0.01
        #expect(meter.filledWidth == 4)
        meter.fraction = 0.5
        #expect(meter.filledWidth == 50)
        meter.fraction = 2
        #expect(meter.filledWidth == 100)
    }
}
