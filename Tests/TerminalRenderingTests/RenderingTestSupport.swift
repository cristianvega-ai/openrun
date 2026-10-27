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
    try cache.update(from: state, atlasGeneration: atlas.generation) {
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
