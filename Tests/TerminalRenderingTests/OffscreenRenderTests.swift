import Foundation
import Metal
import Testing
import TerminalEmulation
import TerminalTheme
@testable import TerminalRendering

@Suite struct OffscreenRenderTests {
    @Test func eachTargetReceivesTheCompletePreparedScreen() throws {
        let screen = try makeScreen("\u{1B}[?25lHello\r\nworld", columns: 10, rows: 3)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try TerminalRenderer(device: device, fonts: testFonts, selectionColor: selectionColor)
        try renderer.prepare(from: screen.state)
        let size = renderer.pixelSize(for: screen.terminal.size)
        let first = try OffscreenTarget(device: device, width: size.width, height: size.height)
        let second = try OffscreenTarget(device: device, width: size.width, height: size.height)
        #expect(renderer.draw(into: first) && renderer.draw(into: second))
        func pixels(_ target: OffscreenTarget) -> [UInt8] {
            _ = target.pixel(x: 0, y: 0)
            var bytes = [UInt8](repeating: 0, count: size.width * size.height * 4)
            target.texture.getBytes(&bytes, bytesPerRow: size.width * 4,
                                    from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
            return bytes
        }
        let firstPixels = pixels(first), secondPixels = pixels(second)
        #expect(firstPixels == secondPixels && Set(firstPixels).count > 3)
    }

    @Test func anOffscreenTargetGivesItsPixelsAndWritesAPNGFile() throws {
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: 4, height: 3)
        var bytes: [UInt8] = [0x03, 0x02, 0x01, 0xFF]
        target.texture.replace(region: MTLRegionMake2D(2, 1, 1, 1), mipmapLevel: 0, withBytes: &bytes, bytesPerRow: 4)
        #expect(target.pixel(x: 2, y: 1) == TerminalColor(red: 1, green: 2, blue: 3))
        let url = FileManager.default.temporaryDirectory.appending(path: "offscreen-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try target.savePNG(to: url)
        #expect(try Data(contentsOf: url).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test(arguments: [TerminalColorScheme.dark, .light])
    func aBlankScreenHasTheGraphiteBackgroundOfTheAppearance(scheme: TerminalColorScheme) throws {
        let screen = try renderScreen("", scheme: scheme)
        #expect(middle(of: screen.target, column: 3, row: 1) == screen.theme.background)
        #expect(screen.target.pixel(x: 0, y: 0) == screen.theme.background)
    }

    @Test func aCellBackgroundHasItsColorOfThePalette() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[41m ")
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.firstSixteenColors[1])
        #expect(middle(of: screen.target, column: 1, row: 0) == screen.theme.background)
    }

    @Test(arguments: [TerminalColorScheme.dark, .light])
    func aFullBlockHasTheGraphiteTextColor(scheme: TerminalColorScheme) throws {
        let screen = try renderScreen("█", scheme: scheme)
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.foreground)
    }

    @Test func aWideCharacterCoversItsTwoCellsAndNoMore() throws {
        let screen = try renderScreen("\u{1B}[?25l日", columns: 6)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 0..<1) > 100)
        #expect(inkCount(of: screen, columns: 2..<6, rows: 0..<3) == 0)
    }

    @Test func anEmojiHasItsOwnColorsAndStaysInsideItsTwoCells() throws {
        let screen = try renderScreen("\u{1B}[?25l🙂", columns: 6)
        let yellow = (0..<2 * testFonts.cellWidth).flatMap { x in (0..<testFonts.cellHeight).map { (x, $0) } }
            .map { screen.target.pixel(x: testPadding + $0, y: testPadding + $1) }.filter { Int($0.red) > Int($0.blue) + 80 }
        #expect(yellow.count > 50)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 0..<1) > 100)
        #expect(inkCount(of: screen, columns: 2..<6, rows: 0..<3) == 0)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 1..<3) == 0)
    }

    @Test func inverseSwapsTheColorsOfTheCellAndItsText() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[7m █")
        #expect(pixel(of: screen.target, x: 0, y: 0) == screen.theme.foreground)
        #expect(middle(of: screen.target, column: 1, row: 0) == screen.theme.background)
    }

    @Test func faintTextHasHalfOfTheStrengthOfItsColor() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[2m█")
        #expect(middle(of: screen.target, column: 0, row: 0) == TerminalColor(red: 130, green: 135, blue: 139))
    }

    @Test func hiddenTextDrawsNothing() throws {
        let screen = try renderScreen("\u{1B}[?25l\u{1B}[8mAB")
        #expect(inkCount(of: screen, columns: 0..<10, rows: 0..<3) == 0)
    }

    @Test(arguments: [TerminalColorScheme.dark, .light])
    func selectedCellsHaveTheGraphiteSelectionColor(scheme: TerminalColorScheme) throws {
        let screen = try renderScreen("\u{1B}[?25lab cd", scheme: scheme, selecting: ViewportCell(column: 0, row: 0))
        #expect(pixel(of: screen.target, column: 0, x: 0, y: 0) == screen.theme.selection)
        #expect(pixel(of: screen.target, column: 1, x: 0, y: 0) == screen.theme.selection)
        #expect(pixel(of: screen.target, column: 3, x: 0, y: 0) == screen.theme.background)
    }
}

/// Run with `OPENRUN_RENDER_OUTPUT=<folder>` to save the renders as PNG files for a review.
private let screenshotFolder = ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"]

@Suite struct ScreenshotTests {
    @Test(.enabled(if: screenshotFolder != nil), arguments: [TerminalColorScheme.dark, .light])
    func theShowcaseScreenInLightAndDark(scheme: TerminalColorScheme) throws {
        let screen = try renderScreen(showcaseScreen, columns: 100, rows: 17, scheme: scheme, selecting: ViewportCell(column: 10, row: 0))
        try screen.target.savePNG(to: URL(fileURLWithPath: "\(screenshotFolder ?? "")/graphite-\(scheme).png"))
    }

    @Test(.enabled(if: screenshotFolder != nil), arguments: ["block": "2", "bar": "6", "underline": "4"])
    func theCursorShapes(name: String, code: String) throws {
        let screen = try renderScreen("cursor\u{1B}[\(code) q", columns: 12, rows: 1)
        try screen.target.savePNG(to: URL(fileURLWithPath: "\(screenshotFolder ?? "")/cursor-\(name).png"))
    }

    @Test(.enabled(if: screenshotFolder != nil))
    func theHollowBlockOfAViewWithoutFocus() throws {
        let screen = try renderScreen("cursor\u{1B}[2 q", columns: 12, rows: 1, isFocused: false)
        try screen.target.savePNG(to: URL(fileURLWithPath: "\(screenshotFolder ?? "")/cursor-hollow-block.png"))
    }

    @Test(.enabled(if: screenshotFolder != nil))
    func theFlashOfTheBell() throws {
        let screen = try renderScreen("$ make\r\nBuild complete!\u{07}\r\n$ ", columns: 30, rows: 4, isFlashing: true)
        try screen.target.savePNG(to: URL(fileURLWithPath: "\(screenshotFolder ?? "")/bell-flash.png"))
    }
}

@Suite struct FrameTimeTests {
    /// Prints the median time of the work that the processor does for a frame.
    @Test func aFullRedrawAndAOneRowChangeAndAScrollOnA160By48Grid() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let theme = TerminalTheme.graphite(for: .dark)
        let terminal = try Terminal(size: TerminalSize(columns: 160, rows: 48), scrollbackLimit: 10_000)
        try theme.apply(to: terminal)
        let state = try RenderState()
        let renderer = try TerminalRenderer(device: device, fonts: testFonts, selectionColor: theme.selection)
        let size = renderer.pixelSize(for: terminal.size)
        let target = try OffscreenTarget(device: device, width: size.width, height: size.height)
        let line = (0..<12).map { "\u{1B}[3\($0 % 7 + 1)mlet value\($0)\u{1B}[0m = render(\"text\") + 日本 " }.joined()
        func frame(_ change: () -> Void) throws -> (milliseconds: Double, rows: Int) {
            change()
            let start = ContinuousClock.now
            try state.update(from: terminal)
            let statistics = try renderer.prepare(from: state)
            state.markClean()
            renderer.draw(into: target)
            let time = start.duration(to: .now).components
            _ = target.pixel(x: 0, y: 0)
            return (Double(time.attoseconds) / 1e15 + Double(time.seconds) * 1e3, statistics.rowsPrepared)
        }
        func median(_ change: @escaping () -> Void) throws -> (milliseconds: Double, rows: Int) {
            let frames = try (0..<40).map { _ in try frame(change) }
            return (frames.map(\.milliseconds).sorted()[20], frames.last?.rows ?? 0)
        }
        _ = try frame { for _ in 0..<48 { terminal.write(line + "\r\n") } }
        let full = try median { for _ in 0..<48 { terminal.write(line + "\r\n") } }
        var column = 0
        let one = try median { terminal.write("\u{1B}[20;\(column % 150 + 1)HX"); column += 1 }
        // The view scrolls up and down in turn, so the viewport stays inside the scrollback.
        var isUp = true
        let row = try median { terminal.scrollViewport(.byRows(isUp ? -1 : 1)); isUp.toggle() }
        let page = try median { terminal.scrollViewport(.byRows(isUp ? -48 : 48)); isUp.toggle() }
        print("FRAME TIMES 160x48 cells, scale 2: full redraw \(full.milliseconds) ms (\(full.rows) rows read), one-row change \(one.milliseconds) ms (\(one.rows) row read)")
        print("FRAME TIMES 160x48 cells, scale 2: scroll by one row \(row.milliseconds) ms (\(row.rows) rows read), scroll by one page \(page.milliseconds) ms (\(page.rows) rows read)")
        #expect(full.rows == 48)
        #expect(one.rows == 1)
        // libghostty-vt marks every row as changed after a scroll, so a scroll reads all rows.
        #expect(row.rows == 48 && page.rows == 48)
    }
}
@Suite struct AtlasFrameTests {
    private func image(_ output: String, markedText: String?, side: Int, name: String) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let theme = TerminalTheme.graphite(for: .dark)
        let terminal = try Terminal(size: TerminalSize(columns: 40, rows: 3), scrollbackLimit: 0)
        try theme.apply(to: terminal)
        terminal.write(output)
        let state = try RenderState()
        try state.update(from: terminal)
        let renderer = try TerminalRenderer(device: device, fonts: testFonts, selectionColor: theme.selection, atlasSide: side)
        try renderer.prepare(from: state)
        renderer.markedText = markedText
        let size = renderer.pixelSize(for: terminal.size)
        let target = try OffscreenTarget(device: device, width: size.width, height: size.height)
        #expect(renderer.draw(into: target))
        _ = target.pixel(x: 0, y: 0)
        if let folder = ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] {
            try target.savePNG(to: URL(fileURLWithPath: "\(folder)/\(name)-\(side).png"))
        }
        var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
        target.texture.getBytes(&pixels, bytesPerRow: size.width * 4,
            from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
        return pixels
    }

    @Test func aFrameWithMoreGlyphsThanTheInitialAtlas() throws {
        let output = "\u{1B}[?25lABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n0123456789abcdefghijklmnopqrstuvwxyz"
        let small = try image(output, markedText: nil, side: 64, name: "atlas-screen")
        let reference = try image(output, markedText: nil, side: 2048, name: "atlas-screen")
        let matches = small.elementsEqual(reference)
        #expect(matches)
    }

    @Test func markedTextCanFillTheAtlasAfterFramePreparation() throws {
        let output = "\u{1B}[?25lAB\u{1B}[2;1H"
        let small = try image(output, markedText: "abcdefghijklmnopqrstuvwxyz", side: 64, name: "atlas-marked")
        let reference = try image(output, markedText: "abcdefghijklmnopqrstuvwxyz", side: 2048, name: "atlas-marked")
        let matches = small.elementsEqual(reference)
        #expect(matches)
    }
}
