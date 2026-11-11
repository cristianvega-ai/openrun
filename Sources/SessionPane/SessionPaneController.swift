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
public final class SessionPaneController: NSObject, TerminalViewDelegate {
    /// The smallest grid that the pane can show (decision of 2026-11-08).
    /// A shell's prompt and input must fit on the screen, or the shell draws
    /// part of them into the scrollback, where nothing can clean them. With
    /// 60 by 12, a command of 600 characters still kept its output and one
    /// prompt through a drag to the minimum and back; 40 by 8 and 50 by 10
    /// did not.
    static let minimumGrid = TerminalSize(columns: 60, rows: 12)
    /// Connects and attaches. Tests give a stand-in, so they need no socket.
    var connect: @Sendable (SessionStart, SocketLocation, SessionSize) throws -> StartedSession = { try $0.attach(at: $1, size: $2) }
    private let start: SessionStart
    private let socket: SocketLocation
    private let work = ConnectionWork()
    private let relay = AttachmentRelay()
    private(set) var attachment: (any AttachedSession)?
    private(set) var view: TerminalView?
    /// The terminal view, once the attach brought the snapshot.
    public var terminalView: TerminalView? { view }
    /// Hears of the title, the minimum size and the end of the session.
    public weak var delegate: SessionPaneDelegate?
    /// The program's title, or the session folder when there is no title.
    public private(set) var title = ""
    /// The view that a host puts in its layout.
    public let paneView = SessionPaneView()
    var hiddenGridLabel: HiddenGridLabel { paneView.hiddenGridLabel }
    private var window: NSWindow? { paneView.window }
    var ask: @MainActor (UserQuestion, NSWindow) async -> Bool = { await $0.ask(in: $1) }
    var isWindowKey: @MainActor (NSWindow) -> Bool = { $0.isKeyWindow }
    private var isAttaching = false
    private var pendingKeyTakeover = false
    private var isClosed = false
    private var hasConnectionFailure = false
    private var folder = ""
    /// The grids that the pane asked for and the session has not applied
    /// yet, oldest first. Until then, the part of the grid that does not fit is
    /// an old size of this pane, not the grid of another client. During a
    /// drag, the session confirms an older grid while newer ones still wait.
    private var ownSizeRequests: [TerminalSize] = []

    /// - Parameter socket: The socket of the session process: the default one, or the one of `--socket`.
    public init(start: SessionStart, socket: SocketLocation) {
        (self.start, self.socket) = (start, socket)
        super.init()
    }

    /// The scale of the screen that the pane shows on, or of the main screen before it shows.
    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// Attaches with the grid that the terminal view will have at the
    /// present size of the pane, so the host lays the pane out first.
    public func attach() {
        let grid = TerminalView.estimatedGrid(for: paneView.bounds.size, scale: scale)
        let (start, socket, connect) = (start, socket, connect)
        isAttaching = true
        work.run({ try connect(start, socket, SessionSize(columns: grid.columns, rows: grid.rows)) }) { [weak self] result in
            self?.attached(result)
        }
    }

    private func attached(_ result: Result<StartedSession, any Error>) {
        isAttaching = false
        // The host can close the pane while it attaches.
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
        // The first layout fits the grid to the pane. When that grid differs
        // from the snapshot, the view reports it, and the pane sends it
        // (decision of 2026-10-25).
        view.waitsForSizeConfirmation = true
        view.delegate = self
        paneView.show(view)
        delegate?.sessionPaneDidChangeMinimumSize(self)
        // Complete the snapshot fit before a later size from another client arrives.
        view.layoutSubtreeIfNeeded()
        // A key event during the attach must follow any earlier foreign size.
        if pendingKeyTakeover, let window, isWindowKey(window), view.gridSize == view.visibleGridSize { view.takeBackGridSize() }
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
                    case .exited: self.delegate?.sessionPaneDidEnd(self)
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
            if let window { _ = await ask(.connectionFailure(detail), window) }
            if !isClosed { delegate?.sessionPaneDidEnd(self) }
        }
    }

    private func showHiddenPart() {
        guard let view, let visible = view.visibleGridSize else { return }
        hiddenGridLabel.show(grid: ownSizeRequests.isEmpty ? view.gridSize : visible, visible: visible)
    }

    /// The host calls this when its window becomes key while the pane has
    /// the keyboard focus. The user uses this pane now, so its size applies
    /// (decision of 2026-10-27).
    public func activate() {
        if let view { view.takeBackGridSize() } else if isAttaching { pendingKeyTakeover = true }
    }

    /// The window stopped being key, or the focus left the pane.
    public func deactivate() {
        pendingKeyTakeover = false
    }

    /// Detaches, and the session goes on. The host calls this once it
    /// removes the pane, also after the end of the session.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        relay.cancel()
        view?.discardPendingOutput()
        if let attachment { detach(attachment) }
    }

    /// A blocked send cannot hold the pane open.
    private func detach(_ attachment: any AttachedSession) {
        work.detach(attachment)
    }

    public func terminalView(_ view: TerminalView, send bytes: [UInt8]) {
        guard !isClosed, !hasConnectionFailure, let attachment else { return }
        send { try attachment.send(input: Data(bytes)) }
    }

    public func terminalViewDidChangeCellSize(_ view: TerminalView) {
        delegate?.sessionPaneDidChangeMinimumSize(self)
    }

    /// The size that holds the smallest grid at the text size of the pane
    /// (decision of 2026-11-08). The host keeps its window at least this
    /// large where the screen has room.
    public var minimumSize: CGSize {
        view?.size(holding: Self.minimumGrid) ?? TerminalView.estimatedSize(holding: Self.minimumGrid, scale: scale)
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

    /// A grid that the pane asked for answers its older requests too. The
    /// session replaces a request with a newer one. Any other grid comes from
    /// another client, and it replaced the requests of this pane.
    public func terminalView(_ view: TerminalView, didApplyGridSize size: TerminalSize) {
        if let index = ownSizeRequests.lastIndex(of: size) { ownSizeRequests.removeFirst(index + 1) } else { ownSizeRequests = [] }
        showHiddenPart()
    }

    public func terminalView(_ view: TerminalView, didChangeVisibleGridSize size: TerminalSize) {
        showHiddenPart()
    }

    public func terminalView(_ view: TerminalView, didChangeTitle title: String) {
        self.title = title.isEmpty ? folder : title
        delegate?.sessionPane(self, didChangeTitle: self.title)
    }

    public func terminalView(_ view: TerminalView, shouldOpenLink address: String) async -> Bool {
        guard !isClosed, let window else { return false }
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
        guard !isClosed, let window else { return false }
        let agreed = await ask(question, window)
        return !isClosed && agreed
    }
}

