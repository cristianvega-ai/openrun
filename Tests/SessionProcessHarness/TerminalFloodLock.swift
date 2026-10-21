import Darwin
import Synchronization

/// A lock for the whole Mac that one test holds while it floods a pseudo
/// terminal with input. Floods that run at the same time slow each other
/// down in the kernel: one 4 MiB transfer alone takes 0.19 s, three at once
/// take 4.2 s each, and nine at once take 24.7 s each. A busy round of
/// three test runs starts up to nine floods, so they take turns here.
///
/// The lock file is in the temporary folder of the user, not in `TMPDIR`,
/// so runs from different work folders find the same file. The file stays
/// after the lock ends, because a second process that opened the old file
/// and one that makes a new file would hold two different locks.
struct TerminalFloodLock: Sendable {
    /// A test process of another run that stops while it holds the lock must
    /// not hold up this run for ever. After this wait the test runs without
    /// the lock, and the lock counts as stuck for the rest of this test
    /// process. A stuck lock costs one wait of this length for the whole
    /// process, not one for each test.
    static let longestWait = Duration.seconds(120)

    private static let pollMicroseconds: UInt32 = 50_000

    /// Set when a wait reached `longestWait`. The tests of one process take
    /// the lock one after the other, so without this mark each of them would
    /// wait the full time in turn.
    private static let lockIsStuck = Atomic<Bool>(false)

    private let descriptor: Int32

    /// Blocks the calling thread, so call it only from `BlockingWork`.
    /// Returns `nil` when the folder or the file cannot be opened, or when
    /// the wait ends first. The test then runs without the lock. While the
    /// lock is stuck, it tries once and returns `nil` at once when another
    /// process still holds the lock. A call that gets the lock clears the
    /// mark.
    static func take() -> TerminalFloodLock? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { return nil }
        let folder = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // The descriptor must not reach a program that the test starts,
        // because that program would keep the lock after the test ends.
        let descriptor = open(folder + "openrun-terminal-floods.lock", O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        let wait = lockIsStuck.load(ordering: .relaxed) ? Duration.zero : longestWait
        let deadline = ContinuousClock.now + wait
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                close(descriptor)
                return nil
            }
            guard ContinuousClock.now < deadline else {
                lockIsStuck.store(true, ordering: .relaxed)
                close(descriptor)
                return nil
            }
            // A blocking flock cannot stop at the deadline.
            usleep(Self.pollMicroseconds)
        }
        lockIsStuck.store(false, ordering: .relaxed)
        return TerminalFloodLock(descriptor: descriptor)
    }

    func give() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
