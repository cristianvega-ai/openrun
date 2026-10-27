import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct DecorationTests {
    private let metrics = testFonts.metrics

    /// The colors along one pixel row of a blank cell that has an SGR `style`.
    private func row(_ style: String, top: Int) throws -> (colors: [TerminalColor], foreground: TerminalColor, background: TerminalColor) {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[\(style)m ")
        let colors = (0..<metrics.width).map { pixel(of: screen.target, x: $0, y: top) }
        return (colors, screen.theme.foreground, screen.theme.background)
    }

    @Test func aSingleUnderlineFillsTheWidthOfTheCell() throws {
        let line = try row("4", top: metrics.underlinePosition)
        #expect(line.colors.allSatisfy { $0 == line.foreground })
        #expect(try row("4", top: 0).colors.allSatisfy { $0 == line.background })
    }

    @Test func aDoubleUnderlineHasAGapBetweenItsLines() throws {
        let upper = try row("4:2", top: metrics.underlinePosition - metrics.underlineThickness)
        #expect(upper.colors.allSatisfy { $0 == upper.foreground })
        #expect(try row("4:2", top: metrics.underlinePosition).colors.allSatisfy { $0 == upper.background })
    }

    @Test func aDottedAndADashedUnderlineLeaveGaps() throws {
        for style in ["4:4", "4:5"] {
            let line = try row(style, top: metrics.underlinePosition)
            let inked = line.colors.filter { $0 == line.foreground }.count
            #expect(inked > 0 && inked < metrics.width)
        }
    }

    @Test func aLineThroughTheTextAndALineOverItHaveTheTextColor() throws {
        let strike = try row("9", top: metrics.strikethroughPosition)
        #expect(strike.colors.allSatisfy { $0 == strike.foreground })
        let over = try row("53", top: 0)
        #expect(over.colors.allSatisfy { $0 == over.foreground })
    }

    @Test func anUnderlineCanHaveItsOwnColor() throws {
        let line = try row("4;58;2;255;0;0", top: metrics.underlinePosition)
        #expect(line.colors.allSatisfy { $0 == TerminalColor(red: 255, green: 0, blue: 0) })
    }
}
