enum ConnectionLimits {
    /// Output may wait for a client up to this many bytes. Past that, it loses
    /// its connection: it can attach again and get a fresh snapshot, but the
    /// session process must not keep an unbounded backlog for it. Snapshots
    /// and screens do not count, because one of them can be larger than the
    /// limit alone. The limit applies to the output queued after them.
    static let queuedOutputByteLimit = 8 * 1024 * 1024
}
