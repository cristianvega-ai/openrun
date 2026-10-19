import Darwin
import Dispatch
import Foundation
import SessionProtocol

final class KeySender: @unchecked Sendable {

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
}
