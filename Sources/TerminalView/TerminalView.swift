import AppKit
import Metal
import TerminalEmulation
import TerminalRendering
import TerminalTheme

/// A terminal on the screen. The view has its own `Terminal` and draws it with
/// Metal in the Graphite colors. Output comes in through `write`.
///
/// The view and its terminal run on the main thread, so they need no lock.
@MainActor
public final class TerminalView: NSView {
    /// SF Mono at 13 points, as the decision of 2026-10-26 says.
    static let defaultPointSize: CGFloat = 13
    let terminal: Terminal
    let state: RenderState
    private(set) var renderer: TerminalRenderer
    /// The colors of the screen. The light version stays until the view follows the appearance.
    private(set) var theme = TerminalTheme.graphite(for: .light)

    /// - Parameter initialGrid: The size of the grid until the view has a size of its own.
    /// - Throws: `RenderingError` when the Mac has no Metal device, or
    ///   `TerminalEmulationError` when the terminal cannot start.
    public init(initialGrid: TerminalSize = TerminalSize(columns: 80, rows: 24)) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderingError.deviceUnavailable }
        terminal = try Terminal(size: initialGrid, scrollbackLimit: 10_000)
        state = try RenderState()
        let fonts = FontSet(pointSize: Self.defaultPointSize, scale: NSScreen.main?.backingScaleFactor ?? 2)
        renderer = try TerminalRenderer(device: device, fonts: fonts, selectionColor: theme.selection)
        super.init(frame: .zero)
        try theme.apply(to: terminal)
    }

    public required init?(coder: NSCoder) {
        fatalError("TerminalView does not come from a storyboard.")
    }

    /// Gives the terminal the bytes that a program wrote. The next frame shows them.
    public func write(_ bytes: some ContiguousBytes) {
        terminal.write(bytes)
    }

    /// Brings the render state up to date and draws one frame into `target`.
    ///
    /// - Returns: `false` when the graphics processor is behind. The caller tries again.
    @discardableResult
    func drawFrame(into target: some RenderTarget) throws -> Bool {
        try state.update(from: terminal)
        try renderer.prepare(from: state)
        guard renderer.draw(into: target) else { return false }
        state.markClean()
        return true
    }
}
