import Foundation
import Metal
import Testing
import TerminalEmulation
import TerminalTheme
@testable import TerminalRendering

/// SF Mono at 13 points on a Retina screen, as the app draws it.
var testFonts: FontSet { FontSet(pointSize: 13, scale: 2) }
/// The selection color of the Graphite theme in dark mode.
var selectionColor: TerminalColor { TerminalTheme.graphite(for: .dark).selection }
/// The space around the grid: 8 points.
var testPadding: Int { Int((8 * testFonts.scale).rounded()) }

/// The cells of text sizes from 6 to 72 points at both backing scales, in pixels.
let drawnCellSizes: [(width: Int, height: Int)] = [6, 9, 11, 13, 17, 24, 36, 50, 72].flatMap { pointSize in
    [1, 2].map { scale in
        let fonts = FontSet(pointSize: CGFloat(pointSize), scale: CGFloat(scale))
        return (fonts.cellWidth, fonts.cellHeight)
    }
}

/// A terminal that already ran `output`, with a render state that read it.
func makeScreen(_ output: String, columns: UInt16 = 20, rows: UInt16 = 3) throws -> (terminal: Terminal, state: RenderState) {
    let terminal = try Terminal(size: TerminalSize(columns: columns, rows: rows), scrollbackLimit: 0)
    terminal.write(output)
    let state = try RenderState()
    try state.update(from: terminal)
    return (terminal, state)
}

func makeAtlas() throws -> GlyphAtlas {
    try GlyphAtlas(device: #require(MTLCreateSystemDefaultDevice()), fonts: testFonts)
}

/// The quadrilaterals of every row of the screen, from the top.
func quadrilaterals(of state: RenderState, atlas: GlyphAtlas) throws -> [RowQuadrilaterals] {
    var rows: [RowQuadrilaterals] = []
    try state.forEachRow(onlyChanged: false) {
        rows.append(try RowQuadrilaterals(row: $0, colors: state.colors, selection: selectionColor, atlas: atlas, metrics: testFonts.metrics))
    }
    return rows
}

/// Brings the cache up to date with the screen, as the renderer does.
func update(_ cache: inout RowCache, from state: RenderState, atlas: GlyphAtlas) throws -> FrameStatistics {
    try cache.update(from: state, colors: state.colors) { row, _ in
        try RowQuadrilaterals(row: row, colors: state.colors, selection: selectionColor, atlas: atlas, metrics: testFonts.metrics)
    }
}

/// Draws a screen with the Graphite theme into an offscreen target.
func renderScreen(
    _ output: String, columns: UInt16 = 10, rows: UInt16 = 3, scheme: TerminalColorScheme = .dark, isFocused: Bool = true,
    selecting cell: ViewportCell? = nil, markedText: String? = nil, markedTextSelection: NSRange? = nil, isFlashing: Bool = false
) throws -> (target: OffscreenTarget, theme: TerminalTheme) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let theme = TerminalTheme.graphite(for: scheme)
    let terminal = try Terminal(size: TerminalSize(columns: columns, rows: rows), scrollbackLimit: 0)
    try theme.apply(to: terminal)
    terminal.write(output)
    if let cell { try terminal.selectWord(at: cell) }
    let state = try RenderState()
    try state.update(from: terminal)
    let renderer = try TerminalRenderer(device: device, fonts: testFonts, selectionColor: theme.selection)
    renderer.isFocused = isFocused
    renderer.markedText = markedText
    renderer.markedTextSelection = markedTextSelection
    renderer.isFlashing = isFlashing
    try renderer.prepare(from: state)
    let size = renderer.pixelSize(for: terminal.size)
    let target = try OffscreenTarget(device: device, width: size.width, height: size.height)
    #expect(renderer.draw(into: target))
    return (target, theme)
}

/// The color of the pixel in the middle of a cell.
func middle(of target: OffscreenTarget, column: Int, row: Int) -> TerminalColor {
    return target.pixel(
        horizontalPosition: testPadding + column * testFonts.cellWidth + testFonts.cellWidth / 2,
        verticalPosition: testPadding + row * testFonts.cellHeight + testFonts.cellHeight / 2)
}

/// How many pixels of a block of cells have another color than the background.
func inkCount(of screen: (target: OffscreenTarget, theme: TerminalTheme), columns: Range<Int>, rows: Range<Int>) -> Int {
    let horizontalPositions = testPadding + columns.lowerBound * testFonts.cellWidth..<testPadding + columns.upperBound * testFonts.cellWidth
    let verticalPositions = testPadding + rows.lowerBound * testFonts.cellHeight..<testPadding + rows.upperBound * testFonts.cellHeight
    return verticalPositions.flatMap { verticalPosition in
        horizontalPositions.map { screen.target.pixel(horizontalPosition: $0, verticalPosition: verticalPosition) }
    }.filter { $0 != screen.theme.background }.count
}

/// The pixel at a place in a cell, counted in pixels from the top left of the cell.
func pixel(of target: OffscreenTarget, column: Int = 0, row: Int = 0,
           horizontalPosition: Int, verticalPosition: Int) -> TerminalColor {
    target.pixel(horizontalPosition: testPadding + column * testFonts.cellWidth + horizontalPosition,
                 verticalPosition: testPadding + row * testFonts.cellHeight + verticalPosition)
}

/// A screen that uses every style that the renderer draws.
let showcaseScreen: String = {
    let escape = "\u{1B}["
    var text = "\(escape)1mOpenRun\(escape)0m terminal view, SF Mono 13 points, Graphite theme, Metal and CoreText\r\n"
    text += "plain \(escape)1mbold\(escape)0m \(escape)3mitalic\(escape)0m \(escape)1;3mbold italic\(escape)0m \(escape)2mfaint\(escape)0m \(escape)7minverse\(escape)0m "
    text += "\(escape)9mstruck\(escape)0m \(escape)53moverline\(escape)0m \(escape)8minvisible\(escape)0m<-invisible\r\n"
    text += "\(escape)4msingle\(escape)0m \(escape)4:2mdouble\(escape)0m \(escape)4:3mcurly\(escape)0m \(escape)4:4mdotted\(escape)0m \(escape)4:5mdashed\(escape)0m "
    text += "\(escape)4:3m\(escape)58;2;232;115;130mred curly\(escape)0m \(escape)1;4mbold under\(escape)0m\r\n"
    for color in 0..<16 { text += "\(escape)38;5;\(color)mcolor\(color)\(escape)0m " }
    text += "\r\n" + (0..<16).map { "\(escape)48;5;\($0)m  \(escape)0m" }.joined() + " \(escape)38;2;255;128;0mtruecolor\(escape)0m\r\n"
    text += "Wide: 日本語のテキスト 한국어 中文字符  Emoji: 🙂 👍 🚀 ✅\r\n"
    text += "Combining: e\u{301} n\u{303}  Devanagari: नमस्ते  Thai: สวัสดี  Greek: αβγ  Cyrillic: жизнь\r\n"
    text += "╭────────────────────╮  ⏺ ⎿ ❯ ✓ ✗ → • … ▌ █ ▓ ▒ ░\r\n│ box drawing joins  │  ⣿⣿ braille ▁▂▃▄▅▆▇█\r\n"
    text += "╰────────────────────╯\r\n\(escape)48;5;4m\(escape)38;5;15m reversed status line \(escape)K\(escape)0m\r\n$ ls -la ~/Projects/openrun\r\n$ "
    return text
}()

/// A frame as agents draw it, with the other characters that the renderer draws in code.
let drawnCharactersScreen = """
    \u{1B}[?25l╭──────────────╮ ┌─┬─┐ ╔═╦═╗ ┏━┳━┓\r
    │ Claude Code  │ ├─┼─┤ ╠═╬═╣ ┣━╋━┫\r
    │ ╭──╮ ┄┄┈┈╌╌  │ └─┴─┘ ╚═╩═╝ ┗━┻━┛\r
    │ ╰──╯ ┆┊╎ ╱╲╳ │ ▁▂▃▄▅▆▇█ ░▒▓ ⣿⣀⡇\r
    ╰──────────────╯ ▖▗▘▙▚▛▜▝▞▟ ⠁⠂⠄⡀\r
    \u{1B}[44;30m main \u{1B}[34;42m\u{E0B0}\u{1B}[30m src \u{1B}[0;32m\u{E0B0}\u{1B}[0m \u{E0B1}\u{E0B3}\u{E0B4}\u{E0B6}\u{E0B8}\u{E0BA}
    """
