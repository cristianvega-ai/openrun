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
    let pointer: PointerInput
    let focus = FocusInput()
    let selection: SelectionInput
    let links: LinkClick
    let scroll = ScrollInput()
    let scrollBar: OverlayScrollBar
    /// The time and the timers of the input. A test gives a clock that it moves.
    let clock: any InputClock
    /// The pasteboard for copy and paste. A test gives another one.
    var pasteboard: any PasteboardAccess = GeneralPasteboard()
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
    private var autoscrollTimer: SelectionAutoscrollTimer?
    private var blink: CursorBlink?
    private var hold: SynchronizedOutputHold?
    private var bellFlash: BellFlash?
    private var pointerShape = PointerShape.text
    private let parser = OutputParser()
    private var isParseScheduled = false
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "TerminalView")

    /// - Parameter initialGrid: The size of the grid until the view has a size of its own.
    /// - Throws: `RenderingError` when the Mac has no Metal device, or
    ///   `TerminalEmulationError` when the terminal cannot start.
    public convenience init(initialGrid: TerminalSize = TerminalSize(columns: 80, rows: 24)) throws {
        try self.init(initialGrid: initialGrid, clock: SystemInputClock())
    }

    init(initialGrid: TerminalSize = TerminalSize(columns: 80, rows: 24), clock: any InputClock) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderingError.deviceUnavailable }
        terminal = try Terminal(size: initialGrid, scrollbackLimit: 10_000)
        state = try RenderState()
        keyboard = try KeyboardInput(terminal: terminal)
        pointer = try PointerInput(terminal: terminal)
        selection = try SelectionInput(terminal: terminal)
        links = LinkClick(terminal: terminal)
        scrollBar = OverlayScrollBar(clock: clock)
        self.clock = clock
        let fonts = FontSet(pointSize: FontSizeControl.standard, scale: NSScreen.main?.backingScaleFactor ?? 2)
        renderer = try TerminalRenderer(device: device, fonts: fonts, selectionColor: theme.selection)
        self.device = device
        host = MetalLayerHost(device: device)
        super.init(frame: .zero)
        wantsLayer = true
        focus.onChange = { [weak self] isKey in self?.windowKeyChanged(isKey) }
        addSubview(scrollBar)
        scrollBar.onScroll = { [weak self] scroll in
            self?.terminal.scrollViewport(scroll)
            self?.requestFrame()
        }
        // A mouse motion with no button comes only through a tracking area.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        blink = CursorBlink(clock: clock) { [weak self] isShown in
            self?.renderer.isCursorShown = isShown
            self?.requestFrame()
        }
        hold = SynchronizedOutputHold(clock: clock) { [weak self] in
            try? self?.terminal.setMode(.synchronizedOutput, enabled: false)
            self?.requestFrame()
        }
        bellFlash = BellFlash(clock: clock) { [weak self] isFlashing in
            self?.renderer.isFlashing = isFlashing
            self?.requestFrame()
        }
        try terminal.setEventHandler(TerminalEventHandler(
            bell: { [weak self] in MainActor.assumeIsolated { self?.bellFlash?.ring() } },
            titleChanged: { [weak self] in MainActor.assumeIsolated { self?.titleChanged() } },
            renderHold: { [weak self] isHeld in MainActor.assumeIsolated { self?.renderHold(isHeld) } }))
        autoscrollTimer = SelectionAutoscrollTimer(clock: clock) { [weak self] in self?.autoscrollSelection() }
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
        if terminal.pointerShape != pointerShape {
            pointerShape = terminal.pointerShape
            window?.invalidateCursorRects(for: self)
        }
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

    func requestFrame() {
        schedule?.requestFrame()
    }

    /// The size of a cell in points.
    var cellSize: CGSize {
        let fonts = renderer.fonts
        return CGSize(width: CGFloat(fonts.cellWidth) / fonts.scale, height: CGFloat(fonts.cellHeight) / fonts.scale)
    }

    /// The space around the grid in points.
    var gridPadding: CGFloat { CGFloat(renderer.padding) / renderer.fonts.scale }

    /// Where the grid is in the view now. The cell size, the grid and the view change often.
    var pointerLocation: PointerLocation {
        PointerLocation(cellSize: cellSize, padding: gridPadding, scale: renderer.fonts.scale, gridSize: terminal.size, viewHeight: bounds.height)
    }

    /// Gives bytes for the program to the delegate. A call with no bytes does nothing.
    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        delegate?.terminalView(self, send: bytes)
    }

    /// Sends bytes that the user typed or pasted. The newest rows come into
    /// view first, so the user sees what the program does with the bytes.
    func sendTyped(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        blink?.keyPressed()
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

    /// The mouse cursor is the shape that the program asked for. It starts as the text cursor.
    var pointerCursor: NSCursor { PointerShapeCursor.cursor(for: pointerShape) }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: pointerCursor)
    }

    public override func keyDown(with event: NSEvent) {
        sendTyped(keyboard.bytes(forKeyDown: event) { interpretKeyEvents([$0]) })
    }

    /// A mouse event that the program does not want selects text.
    public override func mouseDown(with event: NSEvent) {
        // A Command-click on a link is for the link only, also when the program reads the mouse.
        guard !links.press(modifiers: event.modifierFlags, at: pointerLocation.cell(of: point(of: event))) else { return }
        guard !report(.press, .left, event) else { return }
        selection.press(at: point(of: event), in: pointerLocation, timestamp: event.timestamp)
        requestFrame()
    }

    public override func mouseUp(with event: NSEvent) {
        if links.isActive { return links.release(at: pointerLocation.cell(of: point(of: event))) }
        guard !report(.release, .left, event) else { return }
        selection.release(at: point(of: event), in: pointerLocation)
        autoscrollTimer?.update(for: .none)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard !links.isActive, !report(.motion, .left, event) else { return }
        selection.drag(to: point(of: event), in: pointerLocation)
        autoscrollTimer?.update(for: selection.autoscroll)
        requestFrame()
    }

    private func autoscrollSelection() {
        selection.autoscrollTick()
        autoscrollTimer?.update(for: selection.autoscroll)
        scrollBar.reveal()
        requestFrame()
    }

    public override func mouseMoved(with event: NSEvent) { report(.motion, nil, event) }

    public override func rightMouseDown(with event: NSEvent) {
        if !report(.press, .right, event) { super.rightMouseDown(with: event) }
    }

    public override func rightMouseUp(with event: NSEvent) {
        if !report(.release, .right, event) { super.rightMouseUp(with: event) }
    }

    public override func rightMouseDragged(with event: NSEvent) {
        if !report(.motion, .right, event) { super.rightMouseDragged(with: event) }
    }

    public override func otherMouseDown(with event: NSEvent) {
        if !report(.press, PointerInput.button(forNumber: event.buttonNumber), event) { super.otherMouseDown(with: event) }
    }

    public override func otherMouseUp(with event: NSEvent) {
        if !report(.release, PointerInput.button(forNumber: event.buttonNumber), event) { super.otherMouseUp(with: event) }
    }

    public override func otherMouseDragged(with event: NSEvent) {
        if !report(.motion, PointerInput.button(forNumber: event.buttonNumber), event) { super.otherMouseDragged(with: event) }
    }

    private func point(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// Gives a mouse event to the program when the event is for the program.
    ///
    /// - Returns: `false` when the event is not for the program.
    @discardableResult
    private func report(_ action: MouseEvent.Action, _ button: MouseEvent.Button?, _ event: NSEvent) -> Bool {
        guard let bytes = pointer.bytes(action, button: button, modifiers: event.modifierFlags, at: point(of: event), in: pointerLocation) else { return false }
        send(bytes)
        return true
    }

    public override func scrollWheel(with event: NSEvent) {
        // The momentum of a trackpad belongs to the gesture that made it, so only a touch starts a new one.
        let startsGesture = !event.phase.isDisjoint(with: [.began, .mayBegin])
        let action = scroll.action(
            delta: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas, startsGesture: startsGesture,
            cellHeight: cellSize.height, terminal: terminal)
        switch action {
        case .viewport(let rows)?:
            terminal.scrollViewport(.byRows(rows))
            scrollBar.reveal()
            requestFrame()
        case .wheelReports(let button, let count)?:
            let point = convert(event.locationInWindow, from: nil), modifiers = ModifierReader.modifiers(of: event.modifierFlags)
            send((0..<count).flatMap { _ in pointer.reporter.bytes(.press, button: button, modifiers: modifiers, at: point, in: pointerLocation) })
        case .arrowKeys(let isUp, let count)?:
            send((0..<count).flatMap { _ in keyboard.bytes(forArrowUp: isUp) })
        case nil:
            break
        }
    }

    public override func keyUp(with event: NSEvent) {
        sendTyped(keyboard.bytes(forKeyUp: event))
    }

    public override func flagsChanged(with event: NSEvent) {
        sendTyped(keyboard.bytes(forFlagsChanged: event))
    }

    /// Command-C: puts the selected text on the pasteboard, as plain text only.
    @objc public func copy(_ sender: Any?) {
        guard let text = terminal.selectedText(), !text.isEmpty else { return }
        pasteboard.write(plainText: text)
    }

    /// Command-V: sends the plain text of the pasteboard to the program. Text that could run
    /// commands waits for a yes from the delegate. A view with no delegate cannot ask, so it sends nothing.
    @objc public func paste(_ sender: Any?) {
        guard let text = pasteboard.plainText(), !text.isEmpty else { return }
        guard UnsafePasteRule.needsQuestion(for: text, bracketedPaste: terminal.isModeEnabled(.bracketedPaste)) else {
            sendTyped(PasteInput.bytes(for: text, terminal: terminal))
            return
        }
        guard let delegate else { return }
        Task { [weak self] in
            guard let self, await delegate.terminalView(self, shouldPasteUnsafeText: text) else { return }
            sendTyped(PasteInput.bytes(for: text, terminal: terminal))
        }
    }

    // The menu of a later unit sends these actions through the responder chain.
    @objc public func increaseFontSize(_ sender: Any?) { changeFontSize { $0.larger() } }
    @objc public func decreaseFontSize(_ sender: Any?) { changeFontSize { $0.smaller() } }
    @objc public func resetFontSize(_ sender: Any?) { changeFontSize { $0.reset() } }

    /// The menu that gets a key with Command first. It is the main menu until a test gives another one.
    var commandMenu: NSMenu?

    /// Takes the keys that a program wants before the menu and the other views
    /// have them. `KeyEquivalentRoute` tells which keys. A key with Command goes
    /// to the menu first. Then the view runs its own actions: Command-plus and
    /// Command-equals make the text larger, Command-minus smaller, Command-0
    /// goes back to the standard size, and Command-C and Command-V copy and paste.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A window can hold more than one view, and only the view with the keyboard focus takes keys.
        guard window?.firstResponder === self else { return false }
        switch KeyEquivalentRoute.route(for: event, hasMarkedText: keyboard.textInput.hasMarkedText) {
        case .appKit:
            return super.performKeyEquivalent(with: event)
        case .keyDown:
            keyDown(with: event)
        case .menuFirst(let fallback):
            if (commandMenu ?? NSApplication.shared.mainMenu)?.performKeyEquivalent(with: event) == true { return true }
            if let fallback { perform(fallback, with: nil) } else { keyDown(with: event) }
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
        focus.follow(window)
        renderer.isFocused = window?.isKeyWindow ?? true
        if window == nil {
            schedule?.stop()
        } else {
            adoptWindowScale()
            schedule?.attach()
        }
    }

    private func titleChanged() {
        delegate?.terminalView(self, didChangeTitle: terminal.title)
    }

    /// A program holds the screen (mode 2026) or lets it go. libghostty-vt wants the frame
    /// that the program leaves on the screen at the start of the hold, so it is taken here.
    private func renderHold(_ isHeld: Bool) {
        if isHeld {
            try? state.update(from: terminal)
            hold?.begin()
        } else {
            hold?.end()
            requestFrame()
        }
    }

    /// The window became the key window or stopped. The cursor is hollow without it, and the program may want to know.
    private func windowKeyChanged(_ isKey: Bool) {
        renderer.isFocused = isKey
        send(FocusInput.report(gained: isKey, terminal: terminal))
        requestFrame()
    }

    /// Moves the knob of the scroll bar to the place of the viewport.
    func updateScrollBar() {
        scrollBar.update(from: terminal.scrollbar)
    }

    public override func layout() {
        super.layout()
        let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
        scrollBar.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
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
        // While a program holds the screen, the view draws the frame that it took when the hold began.
        if hold?.isHeld != true { try state.update(from: terminal) }
        blink?.update(programBlinks: state.cursor.isBlinking, windowIsKey: renderer.isFocused)
        updateScrollBar()
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
            (new.isFocused, new.markedText, new.isCursorShown, new.isFlashing) = (renderer.isFocused, renderer.markedText, renderer.isCursorShown, renderer.isFlashing)
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
