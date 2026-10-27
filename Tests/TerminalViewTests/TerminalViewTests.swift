import AppKit
import Metal
import QuartzCore
import TerminalEmulation
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

@MainActor @Suite struct SystemInputClockTests {
    @Test func aTimerRunsOnceAfterItsDelayAndACanceledTimerDoesNotRun() {
        let clock = SystemInputClock()
        var runs = 0, canceledRuns = 0
        let timer = clock.schedule(after: .milliseconds(20)) { runs += 1 }
        clock.schedule(after: .milliseconds(20)) { canceledRuns += 1 }.cancel()
        wait(seconds: 3) { runs > 0 }
        wait(seconds: 0.1) { false }
        #expect(runs == 1 && canceledRuns == 0)
        timer.cancel()
    }

    @Test func aRepeatingTimerRunsForEachInterval() {
        let clock = SystemInputClock()
        var runs = 0
        let timer = clock.schedule(after: .milliseconds(10), repeating: .milliseconds(10)) { runs += 1 }
        wait(seconds: 3) { runs >= 3 }
        timer.cancel()
        let count = runs
        wait(seconds: 0.1) { false }
        #expect(count >= 3 && runs == count)
        #expect(clock.now <= ContinuousClock.now)
    }
}

@MainActor @Suite struct TerminalViewTests {
    @Test func outputAppearsInTheColorsOfTheTheme() throws {
        let view = try TerminalView()
        view.write(Array("\u{1B}[?25l█".utf8))
        view.parseTurn()
        let fonts = view.renderer.fonts
        let size = view.renderer.pixelSize(for: view.terminal.size)
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: size.width, height: size.height)
        try view.drawFrame(into: target)
        #expect(target.pixel(x: view.renderer.padding + fonts.cellWidth / 2, y: view.renderer.padding + fonts.cellHeight / 2) == view.theme.foreground)
        #expect(target.pixel(x: size.width - 1, y: size.height - 1) == view.theme.background)
    }

    @Test(.enabled(if: NSScreen.main != nil))
    func aViewInAWindowDrawsItsOutputAndThenWaits() throws {
        let view = try TerminalView()
        let window = show(view)
        defer { window.close() }
        view.write(Array("hello".utf8))
        wait(seconds: 3) { view.framesDrawn > 0 }
        #expect(view.framesDrawn > 0)
        wait(seconds: 0.2) { false }
        let frames = view.framesDrawn
        wait(seconds: 0.3) { false }
        #expect(view.framesDrawn == frames)
        #expect(view.layer is CAMetalLayer)
    }

    @Test func aFloodOfOutputIsParsedInShortTurns() throws {
        let view = try TerminalView()
        view.write([UInt8](repeating: 0x78, count: 32 << 20) + Array("\r\nflood end".utf8))
        let start = ContinuousClock.now
        #expect(view.parseTurn())
        #expect(start.duration(to: .now) < .milliseconds(100))
        var turns = 1
        while view.parseTurn() { turns += 1 }
        #expect(turns > 2)
        #expect(String(decoding: try view.terminal.formatted(.plainText), as: UTF8.self).contains("flood end"))
    }
}

@MainActor @Suite struct SendOfViewTests {
    @Test func theViewGivesBytesToItsDelegateAndSkipsEmptyOnes() throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.send([0x61])
        view.delegate = delegate
        view.send([])
        view.send([0x62, 0x63])
        #expect(delegate.takeSent() == "bc")
    }
}

@MainActor @Suite struct TitleOfViewTests {
    @Test func theDelegateGetsTheTitleOfTheProgramAndTheEndOfTheTitleMakesNoBell() throws {
        let view = try TerminalView()
        view.terminal.write("\u{1B}]2;before\u{07}")
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.terminal.write("\u{1B}]2;My title\u{07}\u{1B}]0;Next\u{1B}\\")
        #expect(delegate.titles == ["My title", "Next"] && !view.renderer.isFlashing)
    }
}

@MainActor @Suite struct GridOfViewTests {
    private func layout(_ view: TerminalView, width: CGFloat, height: CGFloat) {
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    @Test func theGridFitsTheViewAndTheDelegateGetsEachNewSize() throws {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        let fonts = view.renderer.fonts
        func fit(_ width: CGFloat) -> TerminalSize {
            GridFit.grid(for: CGSize(width: width, height: 400), scale: fonts.scale, cell: (fonts.cellWidth, fonts.cellHeight), padding: view.renderer.padding)
        }
        layout(view, width: 800, height: 400)
        #expect(view.gridSize == fit(800))
        layout(view, width: 800, height: 400)
        layout(view, width: 600, height: 400)
        #expect(delegate.sizes == [fit(800), fit(600)])
        #expect(view.terminal.size == fit(600))
        #expect(view.gridSize.columns < fit(800).columns)
    }

    @Test func aViewWithoutSizeKeepsItsGrid() throws {
        let view = try TerminalView(initialGrid: TerminalSize(columns: 30, rows: 5))
        layout(view, width: 0, height: 0)
        #expect(view.gridSize == TerminalSize(columns: 30, rows: 5))
    }
}
