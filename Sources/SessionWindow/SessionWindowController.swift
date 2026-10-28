import AppKit
import SessionConnection
import SessionProtocol
import TerminalEmulation
import TerminalView

/// One window that shows one session. The window attaches off the main
/// thread and makes its view from the snapshot. Then the output of the
/// session goes to the view. Closing the window detaches, and the session
/// goes on.
@MainActor
public final class SessionWindowController: NSObject, NSWindowDelegate {
    /// The first size of the content: 80 columns and 24 rows of the standard text, as in Terminal.
    static let contentSize = CGSize(width: 656, height: 388)
    public let window: NSWindow
    /// Connects and attaches. Tests give a stand-in, so they need no socket.
    var connect: @Sendable (SessionStart, SocketLocation, SessionSize) throws -> StartedSession = { try $0.attach(at: $1, size: $2) }
    private let start: SessionStart
    private let socket: SocketLocation
    private let work = ConnectionWork()
    private(set) var attachment: (any AttachedSession)?
    private(set) var view: TerminalView?
    private var isClosed = false

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
        guard let started = try? result.get() else { return window.close() }
        // The user can close the window while it attaches.
        guard !isClosed else { return detach(started.attachment) }
        // Only the build that made a snapshot can restore it (decision of 2026-10-24).
        guard let view = try? TerminalView(restoring: TerminalSnapshot(bytes: Array(started.attachment.snapshot))) else {
            detach(started.attachment)
            return window.close()
        }
        (attachment, self.view) = (started.attachment, view)
        window.contentView = view
        window.makeFirstResponder(view)
        started.attachment.startReceiving(AttachmentRelay.handler { [weak self] in self?.handle($0) })
    }

    private func handle(_ event: SessionAttachmentEvent) {
        guard !isClosed else { return }
        if case .output(let bytes) = event { view?.write(bytes) }
    }

    public func windowWillClose(_ notification: Notification) {
        isClosed = true
        if let attachment { detach(attachment) }
    }

    /// The detach goes behind the keys that wait, so they still reach the program.
    private func detach(_ attachment: any AttachedSession) {
        work.run { try? attachment.detach(); attachment.shutdown() }
    }
}
