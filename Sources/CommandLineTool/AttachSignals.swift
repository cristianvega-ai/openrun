import Darwin
import Dispatch

/// The signals that `openrun attach` handles, turned into events.
///
/// A handler never writes to the terminal. It asks the terminal writer to
/// end, to suspend, or to follow a change of the window size, so its bytes
/// cannot land in the middle of the output that the writer relays. Raw mode
/// turns off the keys that make SIGINT, SIGQUIT and SIGTSTP, so these come
/// from another process.
final class AttachSignals {
    enum Event: Equatable, Sendable {
        /// SIGINT, SIGTERM, SIGHUP or SIGQUIT: restore the terminal and exit
        /// with 128 plus the signal.
        case stop(signal: Int32)
        /// SIGTSTP: restore the terminal and stop.
        case suspend
        /// SIGCONT: raw mode again, and the screen drawn again.
        case resume
        /// SIGWINCH: the window changed size.
        case resize
    }

    private static let events: [(signal: Int32, event: Event)] = [
        (SIGINT, .stop(signal: SIGINT)),
        (SIGTERM, .stop(signal: SIGTERM)),
        (SIGHUP, .stop(signal: SIGHUP)),
        (SIGQUIT, .stop(signal: SIGQUIT)),
        (SIGTSTP, .suspend),
        (SIGCONT, .resume),
        (SIGWINCH, .resize),
    ]

    private let sources: [DispatchSourceSignal]

    /// Starts to handle the signals. `handler` runs on a queue of its own,
    /// one event at a time. It must not wait for anything, or a later
    /// signal, such as SIGTERM, would wait behind it.
    init(handler: @escaping @Sendable (Event) -> Void) {
        let queue = DispatchQueue(label: "attach.signals")
        sources = Self.events.map { signal, event in
            let source = DispatchSource.makeSignalSource(signal: signal, queue: queue)
            source.setEventHandler { handler(event) }
            source.resume()
            // The signal must not end or stop the process itself. SIGCONT
            // continues a stopped process whatever its action is.
            if signal != SIGCONT { Darwin.signal(signal, SIG_IGN) }
            return source
        }
        // A write to a pipe that nobody reads, such as standard error, must
        // fail instead of ending the process.
        Darwin.signal(SIGPIPE, SIG_IGN)
    }

    func cancel() {
        sources.forEach { $0.cancel() }
    }
}
