import AppKit
import SessionConnection
import SessionProtocol
import TerminalEmulation
import TerminalView

/// One window that shows one session. The window attaches off the main
/// thread and makes its view from the snapshot. Then the output of the
/// session goes to the view, and keys and sizes go to the session. Closing
/// the window detaches, and the session goes on.
@MainActor
public final class SessionWindowController: NSObject, NSWindowDelegate, TerminalViewDelegate {
    /// The first size of the content: 80 columns and 24 rows of the standard text, as in Terminal.
    static let contentSize = CGSize(width: 656, height: 388)
    public let window: NSWindow
    /// Called once when the user closes the window or its program ends.
    public var onClose: (@MainActor () -> Void)?
    /// Connects and attaches. Tests give a stand-in, so they need no socket.
    var connect: @Sendable (SessionStart, SocketLocation, SessionSize) throws -> StartedSession = { try $0.attach(at: $1, size: $2) }
    private let start: SessionStart
    private let socket: SocketLocation
    private let work = ConnectionWork()
    private(set) var attachment: (any AttachedSession)?
    private(set) var view: TerminalView?
    let hiddenGridLabel = HiddenGridLabel()
    var ask: @MainActor (UserQuestion, NSWindow) async -> Bool = { await $0.ask(in: $1) }
    private var isClosed = false
    private var hasConnectionFailure = false
    private var folder = ""

    /// - Parameter socket: The socket of the session process: the default one, or the one of `--socket`.
    public init(start: SessionStart, socket: SocketLocation) {
        (self.start, self.socket) = (start, socket)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        // The controller owns the window, so AppKit must not release it a second time.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    /// Shows the window and attaches with the grid that its view will have.
    public func showWindow() {
        window.makeKeyAndOrderFront(nil)
        let grid = TerminalView.estimatedGrid(for: window.contentLayoutRect.size, scale: window.backingScaleFactor)
        let (start, socket, connect) = (start, socket, connect)
        work.run({ try connect(start, socket, SessionSize(columns: grid.columns, rows: grid.rows)) }) { [weak self] result in
            self?.attached(result)
        }
    }

    private func attached(_ result: Result<StartedSession, any Error>) {
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
        view.delegate = self
        window.contentView = container(holding: view)
        window.makeFirstResponder(view)
        // Complete the snapshot fit before a later size from another client arrives.
        view.layoutSubtreeIfNeeded()
        started.attachment.startReceiving(AttachmentRelay.handler { [weak self] in self?.handle($0) })
    }

    private func handle(_ event: SessionAttachmentEvent) {
        guard !isClosed else { return }
        switch event {
        case .output(let bytes): view?.write(bytes)
        case .sizeChanged(let size):
            view?.followSessionSize(TerminalSize(columns: size.columns, rows: size.rows))
            showHiddenPart()
        case .exited: window.close()
        case .closed, .failed: break
        }
    }

    private func connectionFailed(_ detail: String) {
        guard !isClosed, !hasConnectionFailure else { return }
        hasConnectionFailure = true
        attachment?.shutdown()
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
        hiddenGridLabel.show(grid: view.gridSize, visible: visible)
    }

    /// The user uses this window now, so its size applies (decision of 2026-10-27).
    public func windowDidBecomeKey(_ notification: Notification) {
        view?.takeBackGridSize()
    }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        if let attachment { detach(attachment) }
        onClose?()
    }

    /// The detach goes behind the keys that wait, so they still reach the program.
    private func detach(_ attachment: any AttachedSession) {
        work.run { try? attachment.detach(); attachment.shutdown() }
    }

    public func terminalView(_ view: TerminalView, send bytes: [UInt8]) {
        guard let attachment else { return }
        // A send fails only when the connection is gone, and the receiving thread reports that.
        work.run { try? attachment.send(input: Data(bytes)) }
    }

    public func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize) {
        showHiddenPart()
        guard let attachment else { return }
        work.run { try? attachment.send(size: SessionSize(columns: size.columns, rows: size.rows)) }
    }

    public func terminalView(_ view: TerminalView, didChangeVisibleGridSize size: TerminalSize) {
        showHiddenPart()
    }

    public func terminalView(_ view: TerminalView, didChangeTitle title: String) {
        window.title = title.isEmpty ? folder : title
    }

    public func terminalView(_ view: TerminalView, shouldPasteUnsafeText text: String) async -> Bool {
        await ask(.unsafePaste, window)
    }
}
