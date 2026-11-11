import AppKit
import SessionConnection
import SessionProtocol
import Synchronization
import TerminalEmulation
@testable import SessionWindow
@testable import TerminalView

/// Plays an attached session: it keeps what the window sends, and a test
/// gives it the events of the session.
final class FakeAttachment: AttachedSession {
    struct Record {
        var inputs: [Data] = [], sizes: [SessionSize] = [], detached = false, shutDown = false, sentOnMainThread = false
        var attachSize: SessionSize?
        var confirmationRequests: [SessionSize] = []
        var failsInput = false, failsSize = false, confirmsSizes = true
    }

    let snapshot: Data
    private let earlyEvent: SessionAttachmentEvent?
    let record = Mutex(Record())
    private struct Delivery {
        var handler: (@Sendable (SessionAttachmentEvent) -> Void)?
        var pending: [SessionAttachmentEvent] = []
    }
    private let delivery = Mutex(Delivery())
    private let receiver = DispatchQueue(label: "fake-attachment.receiver")

    /// - Parameter screen: The output that the snapshot of the session holds.
    init(screen: String = "", size: TerminalSize = TerminalSize(columns: 80, rows: 24), earlyEvent: SessionAttachmentEvent? = nil) throws {
        let terminal = try Terminal(size: size, scrollbackLimit: 100)
        terminal.write(screen)
        snapshot = Data(try TerminalSnapshot(capturing: terminal).bytes)
        self.earlyEvent = earlyEvent
    }

    /// A snapshot of other bytes, such as one of another build.
    init(snapshot: Data) {
        self.snapshot = snapshot
        earlyEvent = nil
    }

    func send(input: Data) throws {
        let failed = record.withLock { state in
            state.sentOnMainThread = state.sentOnMainThread || Thread.isMainThread
            if !state.failsInput { state.inputs.append(input) }
            return state.failsInput
        }
        if failed { throw SessionConnectionError.connectionClosed }
    }
    func send(size: SessionSize) throws {
        let failed = record.withLock { state in
            state.sentOnMainThread = state.sentOnMainThread || Thread.isMainThread
            if !state.failsSize { state.sizes.append(size) }
            return state.failsSize
        }
        if failed { throw SessionConnectionError.connectionClosed }
    }
    func send(size: SessionSize, requestsConfirmation: Bool) throws {
        try send(size: size)
        if requestsConfirmation {
            let confirms = record.withLock { state in
                state.confirmationRequests.append(size)
                return state.confirmsSizes
            }
            if confirms { deliver(.sizeChanged(size)) }
        }
    }
    func detach() { record.withLock { $0.detached = true } }
    func shutdown() { record.withLock { $0.shutDown = true } }
    func startReceiving(_ handler: @escaping @Sendable (SessionAttachmentEvent) -> Void) {
        receiver.async { [self] in
            let pending = delivery.withLock { state in
                state.handler = handler
                defer { state.pending = [] }
                return state.pending
            }
            if let earlyEvent { handler(earlyEvent) }
            for event in pending { handler(event) }
        }
    }

    /// Gives an event on the serial receiver, as a real attachment does.
    func deliver(_ event: SessionAttachmentEvent) {
        receiver.async { [self] in
            let handler = delivery.withLock { state in
                if state.handler == nil { state.pending.append(event) }
                return state.handler
            }
            handler?(event)
        }
    }
}

/// A window that attaches to `attachment`, or fails to attach when it is `nil`.
@MainActor
func makeWindowController(_ attachment: FakeAttachment?, folder: String = "/tmp/project") throws -> SessionWindowController {
    // AppKit needs an application object before it makes a window.
    _ = NSApplication.shared
    let controller = SessionWindowController(start: .runningSession(UUID()), socket: try SocketLocation(path: "/tmp/openrun-window-test.socket"))
    controller.ask = { _, _ in true }
    controller.connect = { _, _, size in
        guard let attachment else { throw SessionConnectionError.connectionClosed }
        attachment.record.withLock { $0.attachSize = size }
        return StartedSession(summary: SessionSummary(identifier: UUID(), folder: folder, command: ["/bin/zsh"], size: size, createdAt: Date()), attachment: attachment)
    }
    controller.showWindow()
    return controller
}

/// Lets the main thread work until `condition` is true or `seconds` have passed.
/// The view parses output in turns of the run loop, and the window gets events
/// through the main queue, which runs only while the test waits.
///
/// The wait ends as soon as the condition holds, so the default is long. Other
/// tests of this bundle hold the main thread for seconds, and on a busy Mac a
/// default of 5 seconds ended waits for events that came later.
@MainActor
func waitOnMainThread(seconds: Double = 30, until condition: () -> Bool) async {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end {
        runLoopTurn()
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// One short turn of the main run loop. Swift does not let an async function run it.
@MainActor
private func runLoopTurn() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
}

extension TerminalView {
    /// The text on the screen of the view.
    var screenText: String { String(decoding: (try? terminal.formatted(.plainText)) ?? [], as: UTF8.self) }
}
