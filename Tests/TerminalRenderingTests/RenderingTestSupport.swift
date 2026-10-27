import Metal
import Testing
import TerminalEmulation
import TerminalTheme
@testable import TerminalRendering

/// SF Mono at 13 points on a Retina screen, as the app draws it.
var testFonts: FontSet { FontSet(pointSize: 13, scale: 2) }

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
        rows.append(try RowQuads(row: $0, colors: state.colors, atlas: atlas, metrics: testFonts.metrics))
    }
    return rows
}

/// Brings the cache up to date with the screen, as the renderer does.
func update(_ cache: inout RowCache, from state: RenderState, atlas: GlyphAtlas) throws -> FrameStatistics {
    try cache.update(from: state, atlasGeneration: atlas.generation) {
        try RowQuads(row: $0, colors: state.colors, atlas: atlas, metrics: testFonts.metrics)
    }
}

/// Draws a screen with the Graphite theme into an offscreen target.
func renderScreen(
    _ output: String, columns: UInt16 = 10, rows: UInt16 = 3, scheme: TerminalColorScheme = .dark
) throws -> (target: OffscreenTarget, theme: TerminalTheme) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let theme = TerminalTheme.graphite(for: scheme)
    let terminal = try Terminal(size: TerminalSize(columns: columns, rows: rows), scrollbackLimit: 0)
    try theme.apply(to: terminal)
    terminal.write(output)
    let state = try RenderState()
    try state.update(from: terminal)
    let renderer = try TerminalRenderer(device: device, fonts: testFonts)
    try renderer.prepare(from: state)
    let size = renderer.pixelSize(for: terminal.size)
    let target = try OffscreenTarget(device: device, width: size.width, height: size.height)
    #expect(renderer.draw(into: target))
    return (target, theme)
}

/// The color of the pixel in the middle of a cell.
func middle(of target: OffscreenTarget, column: Int, row: Int) -> TerminalColor {
    let padding = Int((8 * testFonts.scale).rounded())
    return target.pixel(
        x: padding + column * testFonts.cellWidth + testFonts.cellWidth / 2,
        y: padding + row * testFonts.cellHeight + testFonts.cellHeight / 2)
}
