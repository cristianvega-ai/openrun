import AppKit
import Foundation
import Metal
import TerminalEmulation
import TerminalRendering
import TerminalTheme
import os

/// A terminal on the screen. The view has its own `Terminal` and draws it with
/// Metal in the Graphite colors. Output comes in through `write`, and a display
/// link draws the frames.
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
    /// How many frames reached the graphics processor.
    private(set) var framesDrawn = 0
    private let host: MetalLayerHost
    private var schedule: DisplaySchedule?
    private let parser = OutputParser()
    private var isParseScheduled = false
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "TerminalView")

    /// - Parameter initialGrid: The size of the grid until the view has a size of its own.
    /// - Throws: `RenderingError` when the Mac has no Metal device, or
    ///   `TerminalEmulationError` when the terminal cannot start.
    public init(initialGrid: TerminalSize = TerminalSize(columns: 80, rows: 24)) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderingError.deviceUnavailable }
        terminal = try Terminal(size: initialGrid, scrollbackLimit: 10_000)
        state = try RenderState()
        let fonts = FontSet(pointSize: Self.defaultPointSize, scale: NSScreen.main?.backingScaleFactor ?? 2)
        renderer = try TerminalRenderer(device: device, fonts: fonts, selectionColor: theme.selection)
        host = MetalLayerHost(device: device)
        super.init(frame: .zero)
        wantsLayer = true
        schedule = DisplaySchedule(view: self) { [weak self] in self?.drawNextFrame() }
        try theme.apply(to: terminal)
    }

    public required init?(coder: NSCoder) {
        fatalError("TerminalView does not come from a storyboard.")
    }

    /// Keeps the bytes that a program wrote. The view parses them in turns
    /// with a time limit, and the next frame shows them.
    public func write(_ bytes: some ContiguousBytes) {
        parser.append(bytes)
        scheduleParseTurn()
    }

    /// Parses output for at most 4 ms, so a flood of output does not hold the
    /// main thread from drawing and input.
    ///
    /// - Returns: `true` when output is left for another turn.
    @discardableResult
    func parseTurn() -> Bool {
        isParseScheduled = false
        let hasMore = parser.parse(into: terminal, budget: ParseBudget(limit: .milliseconds(4)))
        schedule?.requestFrame()
        if hasMore { scheduleParseTurn() }
        return hasMore
    }

    private func scheduleParseTurn() {
        guard !isParseScheduled else { return }
        isParseScheduled = true
        // A run loop source, not a dispatch block, so events run between two turns.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { _ = self?.parseTurn() }
        }
    }

    public override var isOpaque: Bool { true }

    public override func makeBackingLayer() -> CALayer { host.layer }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { schedule?.stop() } else { schedule?.attach() }
    }

    public override func layout() {
        super.layout()
        host.resize(to: bounds.size, scale: renderer.fonts.scale)
        schedule?.requestFrame()
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
        framesDrawn += 1
        return true
    }

    private func drawNextFrame() {
        do {
            if let target = host.nextTarget(), try drawFrame(into: target) { return }
            // There was no drawable, or the graphics processor is behind. The frame waits for the next step.
            schedule?.requestFrame()
        } catch {
            logger.error("A frame failed: \(String(describing: error), privacy: .private)")
        }
    }
}
