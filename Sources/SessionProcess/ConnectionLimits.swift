/// The limits and deadlines that keep each client of the session process
/// cheap. A client that stops halfway, sends without end, or reads nothing
/// loses its connection instead of holding memory, threads or descriptors.
enum ConnectionLimits {
    /// The most clients at once. Each one costs a reading thread and a
    /// descriptor. The session process refuses more with a failure. A client
    /// counts until its socket is closed, also while its last messages still
    /// go out after it detached, so the limit bounds descriptors and threads.
    static let maximumClientCount = 64

    /// A new connection must deliver its whole hello in this time.
    static let helloTimeLimit: Duration = .seconds(5)

    /// A client may wait as long as it likes between two frames. Once a frame
    /// has started, each part of it must follow within this time.
    static let frameStallLimit: Duration = .seconds(30)

    /// A write to a client that takes no byte for this long ends the client.
    static let writeStallLimit: Duration = .seconds(10)

    /// A client that is closing gets this long to take the messages that wait
    /// for it, such as the exit status of its program at shutdown. Then its
    /// socket closes, also when a write to it is stuck.
    static let closingTimeLimit: Duration = .seconds(2)

    /// Output may wait for a client up to this many bytes. Past that, it loses
    /// its connection: it can attach again and get a fresh snapshot, but the
    /// session process must not keep an unbounded backlog for it. Snapshots
    /// and screens do not count, because one of them can be larger than the
    /// limit alone. The limit applies to the output queued after them.
    static let queuedOutputByteLimit = 8 * 1024 * 1024

    /// The frames that were read from a client and not yet handled may hold
    /// this many bytes, length fields included. Past it, the reading thread
    /// stops reading, the socket fills up, and the client's own sends wait.
    /// A frame that is larger gets in when nothing else waits.
    static let readAheadByteLimit = 1 * 1024 * 1024

    /// At most this many frames may wait to be handled, however small they
    /// are, so a flood of one-byte frames is bounded as well.
    static let readAheadMessageLimit = 1024

    /// When the read-ahead is full, one more control frame of at most this
    /// many bytes may still be read. Input that the program does not read
    /// fills the read-ahead and stays there. Without this reserve the detach
    /// behind it could not be read, and the client could not detach. Input
    /// never takes the reserve, and it holds one frame at a time, so the
    /// read-ahead stays bounded.
    static let controlFrameReserveByteLimit = 1024

    /// How often a reading thread that waits for room in the read-ahead
    /// checks whether its client has left.
    static let peerCheckInterval: Duration = .milliseconds(100)

    /// How long the listener waits after an accept fails for a lack of
    /// descriptors or memory. The waiting connection keeps the socket ready,
    /// so trying again at once could become a busy loop. On macOS each failed
    /// accept also drops one waiting connection, so the wait keeps the loss
    /// small while descriptors are short.
    static let acceptRetryPause: Duration = .milliseconds(250)
}
