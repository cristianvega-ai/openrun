enum ConnectionLimits {

    /// A client may wait as long as it likes between two frames. Once a frame
    /// has started, each part of it must follow within this time.
    static let frameStallLimit: Duration = .seconds(30)
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
}
