import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct OverlayTests {
    @Test func theFlashIsATranslucentRectangleOverTheWholePicture() {
        let quad = OverlayQuads.flash(width: 640, height: 480, color: TerminalColor(red: 255, green: 0, blue: 0))
        #expect(quad.origin == [0, 0] && quad.size == [640, 480])
        #expect(quad.color == [1, 0, 0, 0.3])
    }

    @Test func aFlashMixesTheTextColorIntoEveryPixelAndTheLetterStaysVisible() throws {
        let plain = try renderScreen("\u{1B}[?25lA")
        let flashing = try renderScreen("\u{1B}[?25lA", isFlashing: true)
        let background = plain.theme.background, foreground = plain.theme.foreground
        func mixed(_ from: UInt8, _ toward: UInt8) -> Int { Int((Double(from) * 0.7 + Double(toward) * 0.3).rounded()) }
        let corner = flashing.target.pixel(x: 0, y: 0)
        #expect(abs(Int(corner.red) - mixed(background.red, foreground.red)) <= 1)
        #expect(abs(Int(corner.blue) - mixed(background.blue, foreground.blue)) <= 1)
        #expect(plain.target.pixel(x: 0, y: 0) == background && corner != background)
        // The letter is still there: some pixels of its cell differ from the flash on the background.
        let cell = (0..<testFonts.cellHeight).flatMap { y in (0..<testFonts.cellWidth).map { flashing.target.pixel(x: testPadding + $0, y: testPadding + y) } }
        #expect(cell.filter { $0 != corner }.count > 20)
    }
}
