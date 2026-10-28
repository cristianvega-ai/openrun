import Foundation
import SessionConnection
import SessionProtocol
import Synchronization
import TerminalEmulation
@testable import SessionWindow

/// Plays an attached session: it keeps what the window sends, and a test
/// gives it the events of the session.
final class FakeAttachment: AttachedSession {
    struct Record {
        var inputs: [Data] = [], sizes: [SessionSize] = [], detached = false, shutDown = false, sentOnMainThread = false
    }

    let snapshot: Data
    let record = Mutex(Record())
    private let handler = Mutex<(@Sendable (SessionAttachmentEvent) -> Void)?>(nil)

    /// - Parameter screen: The output that the snapshot of the session holds.
    init(screen: String = "", size: TerminalSize = TerminalSize(columns: 80, rows: 24)) throws {
        let terminal = try Terminal(size: size, scrollbackLimit: 100)
        terminal.write(screen)
        snapshot = Data(try TerminalSnapshot(capturing: terminal).bytes)
    }

    func send(input: Data) { record.withLock { $0.inputs.append(input); $0.sentOnMainThread = $0.sentOnMainThread || Thread.isMainThread } }
    func send(size: SessionSize) { record.withLock { $0.sizes.append(size); $0.sentOnMainThread = $0.sentOnMainThread || Thread.isMainThread } }
    func detach() { record.withLock { $0.detached = true } }
    func shutdown() { record.withLock { $0.shutDown = true } }
    func startReceiving(_ handler: @escaping @Sendable (SessionAttachmentEvent) -> Void) { self.handler.withLock { $0 = handler } }
}

/// Lets the main thread work until `condition` is true or `seconds` have passed.
/// The view parses output in turns of the run loop, and the window gets events
/// through the main queue, which runs only while the test waits.
@MainActor
func waitOnMainThread(seconds: Double = 5, until condition: () -> Bool) async {
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
