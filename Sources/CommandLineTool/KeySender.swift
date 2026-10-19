import Darwin
import Dispatch
import Foundation
import SessionProtocol

/// Reads keys from the terminal and sends them to the session in order.
///
/// A thread of its own reads the keys, and a queue of its own sends them. A
/// send waits while the program reads no input and the session process
/// already holds as much of it as it may, and the keyboard thread must go on
/// reading meanwhile, or it would not see the detach key.
///
/// The keys that wait in this process have a limit, `queuedByteLimit`, for
/// keys that come without end, such as the reports that a terminal sends.
/// At the limit the keyboard thread stops reading until the session takes
/// more, and the terminal holds the keys, as it does for any program that
/// reads slowly. The detach key then waits too, and a signal still ends
/// attaching.
final class KeySender: @unchecked Sendable {
    static let queuedByteLimit = 16 << 20

    /// What the keyboard thread does after its wait for keys ended.
    enum Step: Equatable {
        case waitAgain
        case send([UInt8])
        case detach(keysBefore: [UInt8])
        case endOfInput
    }

    /// What one read of the terminal gave.
    enum KeyRead: Equatable {
        case keys([UInt8])
        case nothing
        case endOfInput
    }

    private let connection: MessageConnection
    private let inputDescriptor: Int32
    private let queue = DispatchQueue(label: "attach.keys")
    // Guarded by `condition`, which also wakes the keyboard thread when the
    // queue has room again.
    private let condition = NSCondition()
    private var queuedBytes = 0
    private var isStopped = false
    private var isPaused = false
    private var detaching = false

    /// `inputDescriptor` is the terminal to read keys from.
    init(connection: MessageConnection, inputDescriptor: Int32 = STDIN_FILENO) {
        self.connection = connection
        self.inputDescriptor = inputDescriptor
    }

    /// Starts the keyboard thread. `onDetach` runs when the user typed the
    /// detach key or the terminal went away, after the detach request went
    /// out or its time ran out.
    func start(onDetach: @escaping @Sendable () -> Void) {
        let keyboard = Thread { [self] in
            readKeys(onDetach: onDetach)
        }
        keyboard.name = "attach.keyboard"
        keyboard.start()
    }

    /// Ends the keyboard thread, also when it waits for room in the queue.
    ///
    /// The keyboard thread reads no key after this call. It may be inside
    /// `poll` when this runs, and a key that arrives then belongs to the
    /// next reader of the terminal, such as the shell. The thread reads under
    /// the same lock that this call takes, so a read cannot start after the
    /// call has returned.
    func stop() {
        condition.lock()
        isStopped = true
        condition.broadcast()
        condition.unlock()
    }

    /// Stops the reading of keys until `resume`. The keyboard thread reads no
    /// key after this call returns, so the keys that the user types meanwhile
    /// stay in the terminal for its next reader, such as the shell. `stop`
    /// still ends the thread while the reading is paused.
    func pause() {
        condition.withLock { isPaused = true }
    }

    /// Lets the keyboard thread read keys again, after a `pause`.
    func resume() {
        condition.lock()
        isPaused = false
        condition.broadcast()
        condition.unlock()
    }

    /// Whether the user detached. A connection that closes after this ended
    /// because of the detach.
    var isDetaching: Bool {
        condition.withLock { detaching }
    }

    /// Reads keys and sends them on until the detach key or the end of input.
    /// The detach key is Control-], the same key that telnet uses. A program
    /// in the session never needs it, and a shell does not use it for
    /// editing. `DetachKeyRecognizer` knows its forms.
    /// It polls with a timeout so it can notice that attaching has ended. When
    /// the recognizer holds the start of a detach form, the timeout is the
    /// time the hold has left, and the held keys go to the session when it ends.
    private func readKeys(onDetach: @Sendable () -> Void) {
        var recognizer = DetachKeyRecognizer()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let idleTimeoutMilliseconds: Int64 = 100
        while true {
            // A paused thread neither polls nor reads, so it cannot take a
            // key that belongs to the shell. `stop` and `resume` wake it.
            let stopped = condition.withLock {
                while isPaused && !isStopped { condition.wait() }
                return isStopped
            }
            if stopped { return }
            var timeoutMilliseconds = idleTimeoutMilliseconds
            if let remaining = recognizer.remainingHold(at: .now) {
                // Round up, so the poll never returns before the hold ends.
                let components = remaining.components
                let milliseconds = components.seconds * 1000 + (components.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
                timeoutMilliseconds = min(idleTimeoutMilliseconds, milliseconds)
            }
            var descriptor = pollfd(fd: inputDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(timeoutMilliseconds))
            let step = Self.step(afterWaiting: ready, recognizer: &recognizer, now: { .now }) {
                // The check and the read are one step under the lock, so
                // `stop` or `pause` either comes first, and nothing is read,
                // or waits for this read, which the poll just promised.
                condition.withLock {
                    if isStopped || isPaused { return .nothing }
                    let count = read(inputDescriptor, &buffer, buffer.count)
                    if count < 0 && (errno == EINTR || errno == EAGAIN) { return .nothing }
                    return count > 0 ? .keys(Array(buffer[0..<count])) : .endOfInput
                }
            }
            switch step {
            case .waitAgain:
                continue
            case .send(let keys):
                guard send(keys) else { return }
            case .detach(let keysBefore):
                // The keys before the detach key go out without waiting for
                // room, so a full queue cannot hold the detach back.
                guard send(keysBefore, waitingForRoom: false) else { return }
                detach(onDetach: onDetach)
                return
            case .endOfInput:
                // The terminal went away. Leave the session running.
                detach(onDetach: onDetach)
                return
            }
        }
    }

    /// One turn of the keyboard thread after `poll` returned `ready`.
    ///
    /// The hold of a detach form counts from when its bytes were read. Keys
    /// that are ready when the wait ends were in the terminal in time, so
    /// they are read and joined to the held keys first, also when this
    /// thread got to them late on a busy Mac. Only a wait that timed out
    /// sends the held keys on. A wait that a signal interrupted does
    /// neither: the next wait uses the time that the hold has left, so a
    /// held Escape never waits for the next key.
    static func step(
        afterWaiting ready: Int32,
        recognizer: inout DetachKeyRecognizer,
        now: () -> ContinuousClock.Instant,
        read: () -> KeyRead
    ) -> Step {
        if ready < 0 { return .waitAgain }
        if ready == 0 {
            let released = recognizer.releaseExpired(at: now())
            return released.isEmpty ? .waitAgain : .send(released)
        }
        switch read() {
        case .nothing:
            return .waitAgain
        case .endOfInput:
            return .endOfInput
        case .keys(let keys):
            let scan = recognizer.scan(keys, at: now())
            return scan.foundDetachKey ? .detach(keysBefore: scan.bytesToSend) : .send(scan.bytesToSend)
        }
    }

    /// Queues keys for the session. Waits while the queue is full, unless
    /// `waitingForRoom` is false, and returns `false` when the keyboard
    /// thread was stopped meanwhile.
    private func send(_ keys: [UInt8], waitingForRoom: Bool = true) -> Bool {
        guard !keys.isEmpty else { return true }
        condition.lock()
        while waitingForRoom && queuedBytes >= Self.queuedByteLimit && !isStopped {
            condition.wait()
        }
        let accepted = !isStopped
        if accepted { queuedBytes += keys.count }
        condition.unlock()
        guard accepted else { return false }
        queue.async { [self] in
            try? connection.send(ClientMessage.input(Data(keys)))
            condition.lock()
            queuedBytes -= keys.count
            condition.broadcast()
            condition.unlock()
        }
        return true
    }

    private func detach(onDetach: @Sendable () -> Void) {
        condition.withLock { detaching = true }
        // The detach request goes behind the keys, and waits for them at most
        // 200 ms: keys that wait for the program hold it back, and detaching
        // must not wait for the program. When the request cannot go out in
        // time, the session process finds the connection closed, and that
        // detaches this client as well.
        let sent = DispatchSemaphore(value: 0)
        queue.async { [connection] in
            try? connection.send(ClientMessage.detach)
            sent.signal()
        }
        _ = sent.wait(timeout: .now() + .milliseconds(200))
        onDetach()
        // The thread that receives output is blocked in a read. Shutting the
        // connection down wakes it.
        connection.shutdown()
    }
}
