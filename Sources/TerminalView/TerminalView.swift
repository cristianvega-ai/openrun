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
    let terminal: Terminal
    let state: RenderState
    let keyboard: KeyboardInput
    private(set) var renderer: TerminalRenderer
    /// The colors of the screen: the Graphite theme of the current appearance.
    private(set) var theme = TerminalTheme.graphite(for: .light)
    private var appearanceObserver: AppearanceObserver?
    public weak var delegate: TerminalViewDelegate?
    /// How many frames reached the graphics processor.
    private(set) var framesDrawn = 0
    private let device: MTLDevice
    private let host: MetalLayerHost
    private var fontSize = FontSizeControl()
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
        keyboard = try KeyboardInput(terminal: terminal)
        let fonts = FontSet(pointSize: FontSizeControl.standard, scale: NSScreen.main?.backingScaleFactor ?? 2)
        renderer = try TerminalRenderer(device: device, fonts: fonts, selectionColor: theme.selection)
        self.device = device
        host = MetalLayerHost(device: device)
        super.init(frame: .zero)
        wantsLayer = true
        schedule = DisplaySchedule(view: self) { [weak self] in self?.drawNextFrame() }
        let observer = AppearanceObserver(appearance: effectiveAppearance)
        appearanceObserver = observer
        try applyTheme(for: observer.scheme)
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

    /// The size of the grid, which fits the size of the view.
    public var gridSize: TerminalSize { terminal.size }

    /// Gives bytes for the program to the delegate. A call with no bytes does nothing.
    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        delegate?.terminalView(self, send: bytes)
    }

    /// Sends bytes that the user typed or pasted. The newest rows come into
    /// view first, so the user sees what the program does with the bytes.
    func sendTyped(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        scrollToBottom()
        send(bytes)
    }

    func scrollToBottom() {
        // A scroll marks every row as changed, so a view at the bottom skips it.
        guard !terminal.isViewportAtBottom else { return }
        terminal.scrollViewport(.toBottom)
        schedule?.requestFrame()
    }

    public override var isOpaque: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        sendTyped(keyboard.bytes(forKeyDown: event))
    }

    public override func keyUp(with event: NSEvent) {
        sendTyped(keyboard.bytes(forKeyUp: event))
    }

    public override func flagsChanged(with event: NSEvent) {
        sendTyped(keyboard.bytes(forFlagsChanged: event))
    }

    // The menu of a later unit sends these actions through the responder chain.
    @objc public func increaseFontSize(_ sender: Any?) { changeFontSize { $0.larger() } }
    @objc public func decreaseFontSize(_ sender: Any?) { changeFontSize { $0.smaller() } }
    @objc public func resetFontSize(_ sender: Any?) { changeFontSize { $0.reset() } }

    /// Command-plus and Command-equals make the text larger, Command-minus
    /// smaller, and Command-0 goes back to 13 points. The view handles them
    /// itself until the menu has items with these keys.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command || modifiers == [.command, .shift] else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "+", "=": increaseFontSize(nil)
        case "-": decreaseFontSize(nil)
        case "0": resetFontSize(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        adoptWindowScale()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard appearanceObserver?.observe(effectiveAppearance) == true, let scheme = appearanceObserver?.scheme else { return }
        do {
            try applyTheme(for: scheme)
        } catch {
            logger.error("The theme failed: \(String(describing: error), privacy: .private)")
        }
    }

    public override func makeBackingLayer() -> CALayer { host.layer }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            schedule?.stop()
        } else {
            adoptWindowScale()
            schedule?.attach()
        }
    }

    public override func layout() {
        super.layout()
        host.resize(to: bounds.size, scale: renderer.fonts.scale)
        fitGrid()
        schedule?.requestFrame()
    }

    /// Gives the terminal as many whole cells as fit in the view, and tells
    /// the delegate when that is a new size.
    private func fitGrid() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fonts = renderer.fonts
        let grid = GridFit.grid(for: bounds.size, scale: fonts.scale, cell: (fonts.cellWidth, fonts.cellHeight), padding: renderer.padding)
        guard grid != terminal.size else { return }
        do {
            try terminal.resize(to: grid)
        } catch {
            logger.error("The grid change failed: \(String(describing: error), privacy: .private)")
            return
        }
        delegate?.terminalView(self, didChangeGridSize: grid)
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

    /// A window on a screen with another scale needs new cells, so the text stays sharp.
    private func adoptWindowScale() {
        guard let scale = window?.backingScaleFactor, scale != renderer.fonts.scale else { return }
        rebuildRenderer(scale: scale)
    }

    private func changeFontSize(_ change: (inout FontSizeControl) -> Bool) {
        if change(&fontSize) { rebuildRenderer(scale: renderer.fonts.scale) }
    }

    /// New cells need a new renderer with its atlas, and a new grid.
    func rebuildRenderer(scale: CGFloat) {
        do {
            let fonts = FontSet(pointSize: fontSize.pointSize, scale: scale)
            let new = try TerminalRenderer(device: device, fonts: fonts, selectionColor: theme.selection)
            (new.isFocused, new.markedText) = (renderer.isFocused, renderer.markedText)
            renderer = new
        } catch {
            logger.error("The renderer failed: \(String(describing: error), privacy: .private)")
            return
        }
        host.resize(to: bounds.size, scale: scale)
        fitGrid()
        schedule?.requestFrame()
    }

    /// A program can still set its own colors, and they stay when the theme changes.
    private func applyTheme(for scheme: TerminalColorScheme) throws {
        theme = .graphite(for: scheme)
        try theme.apply(to: terminal)
        renderer.selectionColor = theme.selection
        schedule?.requestFrame()
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
