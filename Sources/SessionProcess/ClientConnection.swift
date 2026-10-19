import Dispatch
import Foundation
import SessionProtocol
import Synchronization
final class ClientConnection: Sendable {
    /// A message from the client, and the room it takes in the read-ahead.
    struct Received: Sendable {
        let message: ClientMessage
    }

    let messages: AsyncStream<Received>

    private enum Phase {
        case open
        /// Queued messages still go out. Nothing new is queued.
        case closing
        /// The socket is shut down.
        case ended
    }

    private struct State {
        var queuedOutputBytes = 0
        var phase = Phase.open
    }

    private enum Admission {
        case queued
        case refused
        case overLimit
    }

    private let connection: MessageConnection
    private let writeQueue = DispatchQueue(label: "ClientConnection.write")
    private let state = Mutex(State())

    init(connection: MessageConnection) {
        self.connection = connection
        let (stream, continuation) = AsyncStream.makeStream(of: Received.self)
        messages = stream
        let thread = Thread { [weak self] in
            defer {
                continuation.finish()
            }
            do {
                try connection.greetClient()
                while true {
                    let frame = try connection.receive(MessageFrame.self)
                    // The client closed the connection between two frames.
                    guard let frame else { return }
                    let message = try ClientMessage(frame: frame)
                    continuation.yield(Received(message: message))
                }
            } catch {
                self?.endIfOpen()
            }
        }
        thread.name = "ClientConnection.read"
        thread.start()
    }

    /// Queues a message for the client. Never blocks.
    ///
    /// - Parameter countsTowardOutputLimit: Snapshots, screens and the exit
    ///   status pass `false`. See `ConnectionLimits.queuedOutputByteLimit`.
    func send(_ message: ServerMessage, countsTowardOutputLimit: Bool = true) {
        enqueue(message, countsTowardOutputLimit: countsTowardOutputLimit, whenWritten: nil)
    }

    /// Queues a reply that does not count toward the output limit, and
    /// returns once it is written or the connection has ended.
    func sendAndWait(_ message: ServerMessage) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enqueue(message, countsTowardOutputLimit: false) { continuation.resume() }
        }
    }

    func closeAfterSending() {
        let starts = state.withLock { state -> Bool in
            guard state.phase == .open else { return false }
            state.phase = .closing
            return true
        }
        guard starts else { return }
        writeQueue.async { [self] in end() }
    }

    // MARK: - Private


    private func enqueue(_ message: ServerMessage, countsTowardOutputLimit: Bool, whenWritten: (@Sendable () -> Void)?) {
        // The frame is made here, once, so a control message counts the bytes
        // that really go out. A list of many sessions can be large.
        let frame: MessageFrame
        do {
            frame = try message.frame()
        } catch {
            end()
            whenWritten?()
            return
        }
        let size = countsTowardOutputLimit ? Self.countedByteCount(of: frame) : 0
        let admission = state.withLock { state -> Admission in
            guard state.phase == .open else { return .refused }
            if size > 0, state.queuedOutputBytes > 0, state.queuedOutputBytes + size > ConnectionLimits.queuedOutputByteLimit {
                return .overLimit
            }
            state.queuedOutputBytes += size
            // Queued while the lock is held, so the write runs before the last
            // work that `end` queues once it has changed the phase.
            writeQueue.async { [self] in write(frame, countedAs: size, whenWritten: whenWritten) }
            return .queued
        }
        switch admission {
        case .refused:
            whenWritten?()
        case .overLimit:
            end()
            whenWritten?()
        case .queued:
            break
        }
    }

    private func write(_ frame: MessageFrame, countedAs size: Int, whenWritten: (@Sendable () -> Void)?) {
        if !hasEnded {
            do {
                try connection.send(frame)
            } catch {
                end()
            }
        }
        state.withLock { $0.queuedOutputBytes -= size }
        whenWritten?()
    }

    /// Terminal bytes count their payload, as the limit is written. A control
    /// message counts its whole frame.
    private static func countedByteCount(of frame: MessageFrame) -> Int {
        switch frame.kind {
        case .control: MessageFrame.lengthFieldSize + 1 + frame.payload.count
        case .output, .snapshot, .input: frame.payload.count
        }
    }

    private var hasEnded: Bool {
        state.withLock { $0.phase == .ended }
    }

    private func endIfOpen() {
        guard state.withLock({ $0.phase == .open }) else { return }
        end()
    }

    /// Ends the connection at once. Messages that still wait are lost. The
    /// shutdown wakes the reading thread and a write that waits.
    private func end() {
        let ends = state.withLock { state -> Bool in
            guard state.phase != .ended else { return false }
            state.phase = .ended
            return true
        }
        guard ends else { return }
        connection.shutdown()
    }
}
