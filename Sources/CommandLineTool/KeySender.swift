import Darwin
import Dispatch
import Foundation
import SessionProtocol

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
    private var detaching = false

    /// `inputDescriptor` is the terminal to read keys from.
    init(connection: MessageConnection, inputDescriptor: Int32 = STDIN_FILENO) {
        self.connection = connection
        self.inputDescriptor = inputDescriptor
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

    /// Whether the user detached. A connection that closes after this ended
    /// because of the detach.
    var isDetaching: Bool {
        condition.withLock { detaching }
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
