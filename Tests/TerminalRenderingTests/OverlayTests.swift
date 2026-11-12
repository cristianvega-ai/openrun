import Metal
import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct OverlayTests {
    @Test func theFlashIsATranslucentRectangleOverTheWholePicture() {
        let quadrilateral = OverlayQuadrilaterals.flash(width: 640, height: 480, color: TerminalColor(red: 255, green: 0, blue: 0))
        #expect(quadrilateral.origin == [0, 0] && quadrilateral.size == [640, 480])
        #expect(quadrilateral.color == [1, 0, 0, 0.3])
    }

    @Test func aFlashMixesTheTextColorIntoEveryPixelAndTheLetterStaysVisible() throws {
        let plain = try renderScreen("\u{1B}[?25lA")
        let flashing = try renderScreen("\u{1B}[?25lA", isFlashing: true)
        let background = plain.theme.background, foreground = plain.theme.foreground
        func mixed(_ from: UInt8, _ toward: UInt8) -> Int { Int((Double(from) * 0.7 + Double(toward) * 0.3).rounded()) }
        let corner = flashing.target.pixel(horizontalPosition: 0, verticalPosition: 0)
        #expect(abs(Int(corner.red) - mixed(background.red, foreground.red)) <= 1)
        #expect(abs(Int(corner.blue) - mixed(background.blue, foreground.blue)) <= 1)
        #expect(plain.target.pixel(horizontalPosition: 0, verticalPosition: 0) == background && corner != background)
        // The letter is still there: some pixels of its cell differ from the flash on the background.
        let cell = (0..<testFonts.cellHeight).flatMap { verticalPosition in
            (0..<testFonts.cellWidth).map {
                flashing.target.pixel(horizontalPosition: testPadding + $0, verticalPosition: testPadding + verticalPosition)
            }
        }
        #expect(cell.filter { $0 != corner }.count > 20)
    }
}

@Suite struct LinkUnderlineTests {
    @Test func anUnderlinedRunDrawsInTheTextColorAndRedrawsOnlyItsRow() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let screen = try makeScreen("\u{1B}[?25lhttps://a.b\r\nnext", columns: 12, rows: 3)
        let renderer = try TerminalRenderer(device: device, fonts: testFonts, selectionColor: selectionColor)
        let size = renderer.pixelSize(for: screen.terminal.size)
        let metrics = testFonts.metrics
        func underlinePixel(_ target: OffscreenTarget, column: Int) -> TerminalColor {
            target.pixel(horizontalPosition: testPadding + column * metrics.width + 1, verticalPosition: testPadding + metrics.underlinePosition)
        }
        try renderer.prepare(from: screen.state)
        let plain = try OffscreenTarget(device: device, width: size.width, height: size.height)
        #expect(renderer.draw(into: plain))
        renderer.underlinedRuns = [ViewportCellRun(row: 0, columns: 0..<11)]
        let underlined = try OffscreenTarget(device: device, width: size.width, height: size.height)
        #expect(renderer.draw(into: underlined) && renderer.rowsDrawn == 1)
        #expect(underlinePixel(underlined, column: 3) == screen.state.colors.foreground)
        #expect(underlinePixel(underlined, column: 11) == underlinePixel(plain, column: 11))
        #expect(underlinePixel(plain, column: 3) != screen.state.colors.foreground)
    }
}

@Suite struct FindMarkTests {
    @Test func aMarkedRunTintsItsCellsWithTheTextColorAndRedrawsOnlyItsRow() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let screen = try makeScreen("\u{1B}[?25lone two\r\nnext", columns: 12, rows: 3)
        let renderer = try TerminalRenderer(device: device, fonts: testFonts, selectionColor: selectionColor)
        let size = renderer.pixelSize(for: screen.terminal.size)
        // The top left pixel of a cell is over the letters, so it shows the background.
        func corner(_ target: OffscreenTarget, column: Int) -> TerminalColor {
            target.pixel(horizontalPosition: testPadding + column * testFonts.metrics.width, verticalPosition: testPadding)
        }
        try renderer.prepare(from: screen.state)
        let plain = try OffscreenTarget(device: device, width: size.width, height: size.height)
        #expect(renderer.draw(into: plain))
        renderer.markedRuns = [ViewportCellRun(row: 0, columns: 4..<7)]
        let marked = try OffscreenTarget(device: device, width: size.width, height: size.height)
        #expect(renderer.draw(into: marked) && renderer.rowsDrawn == 1)
        let (background, foreground) = (screen.state.colors.background, screen.state.colors.foreground)
        func mixed(_ from: UInt8, _ toward: UInt8) -> Int { Int((Double(from) * 0.78 + Double(toward) * 0.22).rounded()) }
        let tint = corner(marked, column: 4)
        #expect(abs(Int(tint.red) - mixed(background.red, foreground.red)) <= 1 && abs(Int(tint.blue) - mixed(background.blue, foreground.blue)) <= 1)
        #expect(corner(marked, column: 6) == tint && corner(marked, column: 3) == background && corner(marked, column: 7) == background)
        #expect(corner(plain, column: 4) == background)
    }
}
