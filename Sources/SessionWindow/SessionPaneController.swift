import AppKit
import SessionConnection
import SessionProtocol
import TerminalEmulation
import TerminalView

/// One session in a view. It attaches off the main thread and makes its
/// terminal view from the snapshot. Then the output of the session goes to
/// the view, and keys and sizes go to the session. A close detaches, and
/// the session goes on.
@MainActor
public final class SessionPaneController: NSObject, NSWindowDelegate, TerminalViewDelegate {
    /// The first size of the content: 80 columns and 24 rows of the standard text, as in Terminal.
    static let contentSize = CGSize(width: 656, height: 388)
    /// The smallest grid that the window can show (decision of 2026-11-08).
    /// A shell's prompt and input must fit on the screen, or the shell draws
    /// part of them into the scrollback, where nothing can clean them. With
    /// 60 by 12, a command of 600 characters still kept its output and one
    /// prompt through a drag to the minimum and back; 40 by 8 and 50 by 10
    /// did not.
    static let minimumGrid = TerminalSize(columns: 60, rows: 12)
    public let window: NSWindow
    /// Called once when the user closes the window or its program ends.
    public var onClose: (@MainActor () -> Void)?
    /// Connects and attaches. Tests give a stand-in, so they need no socket.
    var connect: @Sendable (SessionStart, SocketLocation, SessionSize) throws -> StartedSession = { try $0.attach(at: $1, size: $2) }
    private let start: SessionStart
    private let socket: SocketLocation
    private let work = ConnectionWork()
    private let relay = AttachmentRelay()
    private(set) var attachment: (any AttachedSession)?
    private(set) var view: TerminalView?
    let hiddenGridLabel = HiddenGridLabel()
    var ask: @MainActor (UserQuestion, NSWindow) async -> Bool = { await $0.ask(in: $1) }
    var isWindowKey: @MainActor (NSWindow) -> Bool = { $0.isKeyWindow }
    private var isAttaching = false
    private var pendingKeyTakeover = false
    private var isClosed = false
    private var hasConnectionFailure = false
    private var folder = ""
    /// The grids that the window asked for and the session has not applied
    /// yet, oldest first. Until then, the part of the grid that does not fit is
    /// an old size of this window, not the grid of another client. During a
    /// drag, the session confirms an older grid while newer ones still wait.
    private var ownSizeRequests: [TerminalSize] = []

    /// - Parameter socket: The socket of the session process: the default one, or the one of `--socket`.
    public init(start: SessionStart, socket: SocketLocation) {
        (self.start, self.socket) = (start, socket)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        // The controller owns the window, so AppKit must not release it a second time.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = TerminalView.estimatedSize(holding: Self.minimumGrid, scale: window.backingScaleFactor)
        window.center()
    }

    /// Shows the window and attaches with the grid that its view will have.
    public func showWindow() {
        window.makeKeyAndOrderFront(nil)
        let grid = TerminalView.estimatedGrid(for: window.contentLayoutRect.size, scale: window.backingScaleFactor)
        let (start, socket, connect) = (start, socket, connect)
        isAttaching = true
        work.run({ try connect(start, socket, SessionSize(columns: grid.columns, rows: grid.rows)) }) { [weak self] result in
            self?.attached(result)
        }
    }

    private func attached(_ result: Result<StartedSession, any Error>) {
        isAttaching = false
        // The user can close the window while it attaches.
        guard !isClosed else {
            if case .success(let started) = result { detach(started.attachment) }
            return
        }
        let started: StartedSession
        switch result {
        case .success(let value): started = value
        case .failure(let error): return connectionFailed("Could not connect to the session. \(error)")
        }
        // Only the build that made a snapshot can restore it (decision of 2026-10-24).
        let view: TerminalView
        do {
            view = try TerminalView(restoring: TerminalSnapshot(bytes: Array(started.attachment.snapshot)))
        } catch {
            detach(started.attachment)
            return connectionFailed("The session screen could not be restored. \(error)")
        }
        (attachment, self.view, folder) = (started.attachment, view, started.summary.folder)
        terminalView(view, didChangeTitle: view.title)
        // The first layout fits the grid to the window. When that grid differs
        // from the snapshot, the view reports it, and the window sends it
        // (decision of 2026-10-25).
        view.waitsForSizeConfirmation = true
        view.delegate = self
        window.contentView = container(holding: view)
        keepMinimumSize(of: view)
        window.makeFirstResponder(view)
        // Complete the snapshot fit before a later size from another client arrives.
        view.layoutSubtreeIfNeeded()
        // A key event during the attach must follow any earlier foreign size.
        if pendingKeyTakeover, isWindowKey(window), view.gridSize == view.visibleGridSize { view.takeBackGridSize() }
        pendingKeyTakeover = false
        started.attachment.startReceiving(relay.handler { [weak self] event, finish in
            guard let self else { finish(); return }
            self.handle(event, finish: finish)
        })
    }

    /// `finish` frees the slot of the event in the relay. The slot stays held until the view applies the
    /// output, and that keeps the relay bounded. A test calls this method to see the order.
    func handle(_ event: SessionAttachmentEvent, finish: @escaping @Sendable () -> Void) {
        guard !isClosed else { finish(); return }
        switch event {
        case .output(let bytes):
            guard let view else { finish(); return }
            view.write(bytes, completion: finish)
        case .sizeChanged(let size, let keepsCursorAtLineStart, let promptRows):
            guard let view else { finish(); return }
            let keeping: PromptKeeping = promptRows.map { .promptRows(aboveCursor: $0) } ?? (keepsCursorAtLineStart ? .cursorRow : .nothing)
            view.followSessionSize(TerminalSize(columns: size.columns, rows: size.rows), keeping: keeping, completion: finish)
        case .exited, .closed, .failed:
            let afterOutput: @MainActor @Sendable () -> Void = { [weak self] in
                if let self, !self.isClosed {
                    switch event {
                    case .exited: self.window.close()
                    case .closed: self.connectionFailed("The session process closed the connection.")
                    case .failed(let error): self.connectionFailed("The session connection failed. \(error)")
                    default: break
                    }
                }
                finish()
            }
            if let view { view.afterPendingOutput(afterOutput) } else { afterOutput() }
        }
    }

    private func connectionFailed(_ detail: String) {
        guard !isClosed, !hasConnectionFailure else { return }
        hasConnectionFailure = true
        if let attachment { work.shutdown(attachment) }
        Task { [weak self] in
            guard let self, !isClosed else { return }
            _ = await ask(.connectionFailure(detail), window)
            if !isClosed { window.close() }
        }
    }

    /// The view fills the window, and the label of the hidden part lies over its bottom right corner.
    private func container(holding view: TerminalView) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        hiddenGridLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        container.addSubview(hiddenGridLabel)
        hiddenGridLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16).isActive = true
        hiddenGridLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8).isActive = true
        return container
    }

    private func showHiddenPart() {
        guard let view, let visible = view.visibleGridSize else { return }
        hiddenGridLabel.show(grid: ownSizeRequests.isEmpty ? view.gridSize : visible, visible: visible)
    }

    /// The user uses this window now, so its size applies (decision of 2026-10-27).
    public func windowDidBecomeKey(_ notification: Notification) {
        if let view { view.takeBackGridSize() } else if isAttaching { pendingKeyTakeover = true }
    }

    public func windowDidResignKey(_ notification: Notification) {
        pendingKeyTakeover = false
    }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        relay.cancel()
        view?.discardPendingOutput()
        if let attachment { detach(attachment) }
        onClose?()
    }

    /// A blocked send cannot hold the window open.
    private func detach(_ attachment: any AttachedSession) {
        work.detach(attachment)
    }

    public func terminalView(_ view: TerminalView, send bytes: [UInt8]) {
        guard !isClosed, !hasConnectionFailure, let attachment else { return }
        send { try attachment.send(input: Data(bytes)) }
    }

    public func terminalViewDidChangeCellSize(_ view: TerminalView) {
        keepMinimumSize(of: view)
    }

    /// A window on a screen of another size can have another minimum.
    public func windowDidChangeScreen(_ notification: Notification) {
        if let view { keepMinimumSize(of: view) }
    }

    /// The window cannot become smaller than the minimum grid at the text size
    /// of its view, or than its screen when that grid does not fit there
    /// (decision of 2026-11-08). A user's drag stops there. A larger text size
    /// can leave the window too small, so it grows, and it moves to stay on its
    /// screen.
    private func keepMinimumSize(of view: TerminalView) {
        let screen = window.screen?.visibleFrame
        var minimum = view.size(holding: Self.minimumGrid)
        if let screen {
            let room = window.contentRect(forFrameRect: screen).size
            minimum = NSSize(width: min(minimum.width, room.width), height: min(minimum.height, room.height))
        }
        window.contentMinSize = minimum
        let current = window.contentLayoutRect.size
        guard current.width < minimum.width || current.height < minimum.height else { return }
        let content = NSSize(width: max(current.width, minimum.width), height: max(current.height, minimum.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        // The top left corner stays, as when the user drags the bottom right one.
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if let screen {
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
            frame.origin.y = max(screen.minY, min(frame.origin.y, screen.maxY - frame.height))
        }
        window.setFrame(frame, display: true)
    }

    public func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize) {
        ownSizeRequests.append(size)
        showHiddenPart()
        guard !isClosed, !hasConnectionFailure, let attachment else { return }
        send { try attachment.send(size: SessionSize(columns: size.columns, rows: size.rows), requestsConfirmation: true) }
    }

    private func send(_ operation: @escaping @Sendable () throws -> Void) {
        let report: @MainActor @Sendable (String) -> Void = { [weak self] in self?.connectionFailed($0) }
        work.run {
            do { try operation() } catch {
                let detail = "The session connection failed. \(error)"
                DispatchQueue.main.async { MainActor.assumeIsolated { report(detail) } }
            }
        }
    }

    /// A grid that the window asked for answers its older requests too. The
    /// session replaces a request with a newer one. Any other grid comes from
    /// another client, and it replaced the requests of this window.
    public func terminalView(_ view: TerminalView, didApplyGridSize size: TerminalSize) {
        if let index = ownSizeRequests.lastIndex(of: size) { ownSizeRequests.removeFirst(index + 1) } else { ownSizeRequests = [] }
        showHiddenPart()
    }

    public func terminalView(_ view: TerminalView, didChangeVisibleGridSize size: TerminalSize) {
        showHiddenPart()
    }

    public func terminalView(_ view: TerminalView, didChangeTitle title: String) {
        window.title = title.isEmpty ? folder : title
    }

    public func terminalView(_ view: TerminalView, shouldOpenLink address: String) async -> Bool {
        guard !isClosed else { return false }
        let agreed = await ask(.openLink(address), window)
        return !isClosed && agreed
    }

    public func terminalView(_ view: TerminalView, shouldPasteUnsafeText text: String) async -> Bool {
        await agrees(to: .unsafePaste)
    }

    public func terminalView(_ view: TerminalView, shouldInsertUnsafeText text: String) async -> Bool {
        await agrees(to: .unsafeInsertion)
    }

    private func agrees(to question: UserQuestion) async -> Bool {
        guard !isClosed else { return false }
        let agreed = await ask(question, window)
        return !isClosed && agreed
    }
}

/// The pane still owns its window. The next changes give the window a
/// controller of its own around the pane.
public typealias SessionWindowController = SessionPaneController
