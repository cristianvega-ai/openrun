import Darwin
import Dispatch

/// Turns the signals that ask the session process to stop into a value to
/// wait for.
final class ShutdownSignals: @unchecked Sendable {
    private let sources: [DispatchSourceSignal]
    private let received: AsyncStream<Int32>

    /// SIGHUP is included because closing the terminal window that runs the
    /// session process should stop it cleanly instead of leaving its socket.
    init() {
        let handled = [SIGTERM, SIGINT, SIGHUP]
        let (stream, continuation) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
        received = stream
        // The default action would end the process on the spot. Ignoring the
        // signal lets the dispatch source see it instead.
        handled.forEach { signal($0, SIG_IGN) }
        // A client that disappears must fail a write, not end the process.
        signal(SIGPIPE, SIG_IGN)
        sources = handled.map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { continuation.yield(number) }
            source.resume()
            return source
        }
    }

    /// Returns the number of the first signal that asks the process to stop.
    func wait() async -> Int32 {
        for await number in received { return number }
        return SIGTERM
    }
}
