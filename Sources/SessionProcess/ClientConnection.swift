import Dispatch
import Foundation
import SessionProtocol
import Synchronization

/// One client of the session process.
///
/// Reading and writing each have a thread of their own, so a client that
/// stops reading blocks only its own writes and never a session. The limits
/// and deadlines in `ConnectionLimits` bound what each client costs.
final class ClientConnection: Sendable {
    /// A message from the client, and the room it takes in the read-ahead.
    struct Received: Sendable {
        let message: ClientMessage
        fileprivate let byteCount: Int
        fileprivate let room: ReadAhead.Room
    }

    /// Messages from the client, in order. The stream finishes when the client
    /// leaves, when the handshake fails, or when the connection ends. Call
    /// `markHandled` for each message once it is dealt with.
    let messages: AsyncStream<Received>

    private enum Phase {
        case open
        /// Queued messages still go out. Nothing new is queued.
        case closing
        /// The socket is shut down.
        case ended
    }

    private struct OutputWaiter {
        let identifier: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var queuedOutputBytes = 0
        var writtenOutputBytes = 0
        var snapshotGraceDeadline: ContinuousClock.Instant?
        var outputWaiter: OutputWaiter?
        var outputProgressObserver: (@Sendable () -> Void)?
        var refusesOutputRoomWait = false
        var programHasExited = false
        var nextOutputWaiterIdentifier: UInt64 = 0
        var phase = Phase.open
        var hasLeft = false
        var leaveHandlers: [@Sendable () -> Void] = []
        /// The reading thread has returned.
        var readingHasStopped = false
        /// The write queue has run its last work, after the connection ended.
        var writingHasStopped = false
        /// The descriptor is closed.
        var isClosed = false
        var closeWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private enum Admission {
        case queued
        case refused
        case overLimit
    }

    private let connection: MessageConnection
    private let writeQueue = DispatchQueue(label: "ClientConnection.write")
    private let state = Mutex(State())
    private let readAhead = ReadAhead()

    init(connection: MessageConnection) {
        self.connection = connection
        let (stream, continuation) = AsyncStream.makeStream(of: Received.self)
        messages = stream
        // A blocking read cannot be an async task, because it would hold one
        // of the few threads that Swift concurrency owns. For the same reason
        // the thread, and not a task, waits for room in the read-ahead.
        let readAhead = readAhead
        let thread = Thread { [weak self] in
            defer {
                continuation.finish()
                self?.clientLeft()
                self?.readingStopped()
            }
            do {
                try connection.greetClient(within: ConnectionLimits.helloTimeLimit, capabilities: ServerCapabilities(orderedResizeConfirmation: true))
                while true {
                    var byteCount = 0
                    var room = ReadAhead.Room.shared
                    let frame = try connection.receive(MessageFrame.self, timeLimit: .stall(ConnectionLimits.frameStallLimit)) { frameByteCount, kind in
                        guard let admitted = readAhead.admit(frameByteCount, isControl: kind == .control, peerHasClosed: { connection.peerHasClosed }) else {
                            throw SessionProtocolError.connectionClosed
                        }
                        byteCount = frameByteCount
                        room = admitted
                    }
                    // The client closed the connection between two frames.
                    guard let frame else { return }
                    let message: ClientMessage
                    do {
                        message = try ClientMessage(frame: frame)
                    } catch where frame.kind == .control {
                        // A request that cannot be read gets an answer that
                        // names the problem, then the connection closes.
                        self?.refuse(because: error)
                        return
                    }
                    continuation.yield(Received(message: message, byteCount: byteCount, room: room))
                }
            } catch {
                // A client that breaks the protocol, misses a deadline, or
                // leaves while it waits for room ends its own connection. A
                // connection that is closing stops reading here too, and its
                // queued messages, such as the exit status, still go out.
                self?.endIfOpen()
            }
        }
        thread.name = "ClientConnection.read"
        thread.start()
    }

    /// Runs `handler` once the client has left or its connection has ended.
    /// Runs it at once when that already happened.
    func whenClientLeaves(_ handler: @escaping @Sendable () -> Void) {
        let hasLeft = state.withLock { state -> Bool in
            if !state.hasLeft { state.leaveHandlers.append(handler) }
            return state.hasLeft
        }
        if hasLeft { handler() }
    }

    /// Returns once the connection has ended, both of its threads are done
    /// with the socket, and the descriptor is closed. After
    /// `closeAfterSending`, that takes at most about
    /// `ConnectionLimits.closingTimeLimit`.
    func waitUntilClosed() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isClosed = state.withLock { state -> Bool in
                if !state.isClosed { state.closeWaiters.append(continuation) }
                return state.isClosed
            }
            if isClosed { continuation.resume() }
        }
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

    /// The bytes that count toward the output limit, or nil after closing.
    var queuedOutputBytes: Int? {
        state.withLock { $0.phase == .open ? $0.queuedOutputBytes : nil }
    }

    var hasOutputRoomWaiter: Bool {
        state.withLock { $0.outputWaiter != nil }
    }

    /// A new viewer must show real progress before it takes precedence over
    /// another viewer. A small socket buffer alone is not enough.
    var hasMadeOutputProgress: Bool {
        state.withLock { $0.writtenOutputBytes >= ConnectionLimits.outputLowMark }
    }

    func allowLargeSnapshotRestoration(byteCount: Int) {
        guard byteCount >= ConnectionLimits.largeSnapshotByteLimit else { return }
        state.withLock { $0.snapshotGraceDeadline = .now + ConnectionLimits.largeSnapshotGraceTimeLimit }
    }

    /// Waits without holding an actor or a thread. A client that cannot
    /// make enough room by the deadline loses its connection.
    func waitForOutputRoom(onWaiting: @Sendable () -> Void = {}) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let wait = state.withLock { state -> (UInt64, Duration)? in
                guard state.phase == .open, !state.refusesOutputRoomWait,
                      state.queuedOutputBytes >= ConnectionLimits.outputHighMark else { return nil }
                guard state.outputWaiter == nil else { return nil }
                state.nextOutputWaiterIdentifier &+= 1
                let identifier = state.nextOutputWaiterIdentifier
                state.outputWaiter = OutputWaiter(identifier: identifier, continuation: continuation)
                let grace = state.snapshotGraceDeadline.map { $0 - .now } ?? .zero
                let limit = state.programHasExited
                    ? ConnectionLimits.outputRoomTimeLimit
                    : max(ConnectionLimits.outputRoomTimeLimit, grace)
                return (identifier, limit)
            }
            guard let (identifier, duration) = wait else {
                continuation.resume()
                return
            }
            onWaiting()
            let parts = duration.components
            let delay = DispatchTimeInterval.nanoseconds(Int(parts.seconds) * 1_000_000_000 + Int(parts.attoseconds / 1_000_000_000))
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.end(waitingForOutput: identifier)
            }
        }
    }

    func observeOutputProgress(_ observer: (@Sendable () -> Void)?) {
        state.withLock { $0.outputProgressObserver = observer }
    }

    /// Lets a session that detaches or ends continue without this client.
    func stopWaitingForOutputRoom() {
        let waiter = state.withLock { state -> OutputWaiter? in
            defer { state.outputWaiter = nil }
            return state.outputWaiter
        }
        waiter?.continuation.resume()
    }

    /// The remaining output after the program exits gets the normal room
    /// deadline, so a large snapshot grace cannot hold the session.
    func programDidExit() {
        state.withLock { $0.programHasExited = true }
        stopWaitingForOutputRoom()
    }

    /// A client that detaches or a session that ends must not start a new wait.
    /// The flag covers the time before the waiter is installed.
    func refuseOutputRoomWait() {
        state.withLock { $0.refusesOutputRoomWait = true }
        stopWaitingForOutputRoom()
    }

    /// A faster viewer must not stay behind this client's full queue. The
    /// queue can drain between the session's check and this call, so the
    /// decision and the close use the same lock.
    func endForOutputBackpressure() { end(onlyIfFull: true) }

    /// Frees the message's room in the read-ahead, so the reading thread can
    /// read on.
    func markHandled(_ received: Received) {
        readAhead.release(received.byteCount, from: received.room)
    }

    /// Closes the connection once every queued message has gone out, or after
    /// `ConnectionLimits.closingTimeLimit`, whichever comes first. A client
    /// that reads nothing then cannot keep its descriptor and thread.
    func closeAfterSending() {
        let starts = state.withLock { state -> Bool in
            guard state.phase == .open else { return false }
            state.phase = .closing
            return true
        }
        guard starts else { return }
        // No more messages are handled, so a reading thread that waits for
        // room stops.
        readAhead.close()
        writeQueue.async { [self] in end() }
        let parts = ConnectionLimits.closingTimeLimit.components
        let delay = DispatchTimeInterval.nanoseconds(Int(parts.seconds) * 1_000_000_000 + Int(parts.attoseconds / 1_000_000_000))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.end()
        }
    }

    // MARK: - Private

    /// Answers a request that cannot be read with a failure that names the
    /// problem, and closes the connection once the answer has gone out.
    private func refuse(because error: any Error) {
        enqueue(.failure(SessionFailure(reason: .invalidRequest, message: "\(error)")), countsTowardOutputLimit: false, whenWritten: nil)
        closeAfterSending()
    }

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
        var outputWasWritten = false
        if !hasEnded {
            do {
                try connection.send(frame, stallLimit: ConnectionLimits.writeStallLimit)
                outputWasWritten = frame.kind == .output
            } catch {
                end()
            }
        }
        let result = state.withLock { state -> (OutputWaiter?, (@Sendable () -> Void)?) in
            state.queuedOutputBytes -= size
            if outputWasWritten { state.writtenOutputBytes += size }
            guard state.queuedOutputBytes <= ConnectionLimits.outputLowMark else { return (nil, nil) }
            if state.outputWaiter != nil { state.snapshotGraceDeadline = nil }
            defer { state.outputWaiter = nil }
            let observer = state.phase == .open && state.writtenOutputBytes >= ConnectionLimits.outputLowMark
                ? state.outputProgressObserver : nil
            return (state.outputWaiter, observer)
        }
        result.0?.continuation.resume()
        result.1?()
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
    private func end(waitingForOutput identifier: UInt64? = nil, onlyIfFull: Bool = false) {
        let result = state.withLock { state -> (Bool, OutputWaiter?) in
            guard state.phase != .ended else { return (false, nil) }
            if let identifier, state.outputWaiter?.identifier != identifier { return (false, nil) }
            if onlyIfFull, state.queuedOutputBytes < ConnectionLimits.outputHighMark { return (false, nil) }
            state.phase = .ended
            defer { state.outputWaiter = nil }
            return (true, state.outputWaiter)
        }
        guard result.0 else { return }
        result.1?.continuation.resume()
        readAhead.close()
        connection.shutdown()
        clientLeft()
        // Every write was queued before the phase changed, and none after. So
        // when this runs, the write queue is done with the socket.
        writeQueue.async { [self] in writingStopped() }
    }

    private func clientLeft() {
        let handlers = state.withLock { state -> [@Sendable () -> Void] in
            guard !state.hasLeft else { return [] }
            state.hasLeft = true
            defer { state.leaveHandlers.removeAll() }
            return state.leaveHandlers
        }
        handlers.forEach { $0() }
    }

    private func readingStopped() {
        state.withLock { $0.readingHasStopped = true }
        closeWhenUnused()
    }

    private func writingStopped() {
        state.withLock { $0.writingHasStopped = true }
        closeWhenUnused()
    }

    /// Closes the descriptor once neither thread uses it, and wakes those
    /// that wait for it. Until then the client keeps its place among the
    /// clients that the session process serves.
    private func closeWhenUnused() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            guard state.readingHasStopped, state.writingHasStopped, !state.isClosed else { return [] }
            connection.close()
            state.isClosed = true
            defer { state.closeWaiters.removeAll() }
            return state.closeWaiters
        }
        waiters.forEach { $0.resume() }
    }
}
