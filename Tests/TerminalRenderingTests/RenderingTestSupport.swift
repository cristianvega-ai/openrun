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

/// The quads of every row of the screen, from the top.
func quads(of state: RenderState, atlas: GlyphAtlas) throws -> [RowQuads] {
    var rows: [RowQuads] = []
    try state.forEachRow(onlyChanged: false) {
        rows.append(try RowQuads(row: $0, colors: state.colors, selection: selectionColor, atlas: atlas, metrics: testFonts.metrics))
    }
    return rows
}

/// Brings the cache up to date with the screen, as the renderer does.
func update(_ cache: inout RowCache, from state: RenderState, atlas: GlyphAtlas) throws -> FrameStatistics {
    try cache.update(from: state, colors: state.colors, atlasGeneration: atlas.generation) {
        try RowQuads(row: $0, colors: state.colors, selection: selectionColor, atlas: atlas, metrics: testFonts.metrics)
    }
}

/// Draws a screen with the Graphite theme into an offscreen target.
func renderScreen(
    _ output: String, columns: UInt16 = 10, rows: UInt16 = 3, scheme: TerminalColorScheme = .dark, isFocused: Bool = true,
    selecting cell: ViewportCell? = nil, markedText: String? = nil
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
    try renderer.prepare(from: state)
    let size = renderer.pixelSize(for: terminal.size)
    let target = try OffscreenTarget(device: device, width: size.width, height: size.height)
    #expect(renderer.draw(into: target))
    return (target, theme)
}

/// The color of the pixel in the middle of a cell.
func middle(of target: OffscreenTarget, column: Int, row: Int) -> TerminalColor {
    return target.pixel(
        x: testPadding + column * testFonts.cellWidth + testFonts.cellWidth / 2,
        y: testPadding + row * testFonts.cellHeight + testFonts.cellHeight / 2)
}

/// How many pixels of a block of cells have another color than the background.
func inkCount(of screen: (target: OffscreenTarget, theme: TerminalTheme), columns: Range<Int>, rows: Range<Int>) -> Int {
    let xs = testPadding + columns.lowerBound * testFonts.cellWidth..<testPadding + columns.upperBound * testFonts.cellWidth
    let ys = testPadding + rows.lowerBound * testFonts.cellHeight..<testPadding + rows.upperBound * testFonts.cellHeight
    return ys.flatMap { y in xs.map { screen.target.pixel(x: $0, y: y) } }.filter { $0 != screen.theme.background }.count
}

/// The pixel at a place in a cell, counted in pixels from the top left of the cell.
func pixel(of target: OffscreenTarget, column: Int = 0, row: Int = 0, x: Int, y: Int) -> TerminalColor {
    target.pixel(x: testPadding + column * testFonts.cellWidth + x, y: testPadding + row * testFonts.cellHeight + y)
}

/// A screen that uses every style that the renderer draws.
let showcaseScreen: String = {
    let e = "\u{1B}["
    var text = "\(e)1mOpenRun\(e)0m terminal view, SF Mono 13 points, Graphite theme, Metal and CoreText\r\n"
    text += "plain \(e)1mbold\(e)0m \(e)3mitalic\(e)0m \(e)1;3mbold italic\(e)0m \(e)2mfaint\(e)0m \(e)7minverse\(e)0m "
    text += "\(e)9mstruck\(e)0m \(e)53moverline\(e)0m \(e)8minvisible\(e)0m<-invisible\r\n"
    text += "\(e)4msingle\(e)0m \(e)4:2mdouble\(e)0m \(e)4:3mcurly\(e)0m \(e)4:4mdotted\(e)0m \(e)4:5mdashed\(e)0m "
    text += "\(e)4:3m\(e)58;2;232;115;130mred curly\(e)0m \(e)1;4mbold under\(e)0m\r\n"
    for color in 0..<16 { text += "\(e)38;5;\(color)mcolor\(color)\(e)0m " }
    text += "\r\n" + (0..<16).map { "\(e)48;5;\($0)m  \(e)0m" }.joined() + " \(e)38;2;255;128;0mtruecolor\(e)0m\r\n"
    text += "Wide: 日本語のテキスト 한국어 中文字符  Emoji: 🙂 👍 🚀 ✅\r\n"
    text += "Combining: e\u{301} n\u{303}  Devanagari: नमस्ते  Thai: สวัสดี  Greek: αβγ  Cyrillic: жизнь\r\n"
    text += "╭────────────────────╮  ⏺ ⎿ ❯ ✓ ✗ → • … ▌ █ ▓ ▒ ░\r\n│ box drawing joins  │  ⣿⣿ braille ▁▂▃▄▅▆▇█\r\n"
    text += "╰────────────────────╯\r\n\(e)48;5;4m\(e)38;5;15m reversed status line \(e)K\(e)0m\r\n$ ls -la ~/Projects/openrun\r\n$ "
    return text
}()
