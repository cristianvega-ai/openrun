import Foundation

/// Counts the frames that were read from a client and not yet handled, and
/// holds the reading thread while they are too many.
///
/// Each frame counts its size, length field included, and counts as one
/// message. `ConnectionLimits` gives both limits. A client that sends faster
/// than its program reads then meets backpressure on its own socket, and
/// cannot make the session process read, decode or keep more.
///
/// One small control frame may go past the limits, into a reserve. Input that
/// waits for the program can fill the read-ahead for as long as the program
/// reads nothing, and the client must still be able to detach.
final class ReadAhead: @unchecked Sendable {
    /// Where an admitted frame counts until it is handled.
    enum Room: Sendable {
        /// Within the limits.
        case shared
        /// In the reserve for one control frame of at most
        /// `ConnectionLimits.controlFrameReserveByteLimit` bytes.
        case reserve
    }

    private let condition = NSCondition()
    private var unhandledBytes = 0
    private var unhandledMessages = 0
    private var reserveIsTaken = false
    private var isClosed = false

    /// Waits until a frame of this size and kind has room, and returns where
    /// it counts.
    ///
    /// A client can leave while its thread waits here, and its socket then
    /// shows nothing until the thread reads again. So the wait asks
    /// `peerHasClosed` every `ConnectionLimits.peerCheckInterval`.
    ///
    /// Returns `nil` once the connection is closing or the client has left.
    func admit(_ byteCount: Int, isControl: Bool, peerHasClosed: () -> Bool) -> Room? {
        condition.lock()
        defer { condition.unlock() }
        while !isClosed {
            if let room = room(for: byteCount, isControl: isControl) {
                switch room {
                case .shared:
                    unhandledBytes += byteCount
                    unhandledMessages += 1
                case .reserve:
                    reserveIsTaken = true
                }
                return room
            }
            let parts = ConnectionLimits.peerCheckInterval.components
            let interval = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            condition.wait(until: Date(timeIntervalSinceNow: interval))
            if !isClosed, room(for: byteCount, isControl: isControl) == nil, peerHasClosed() { return nil }
        }
        return nil
    }

    /// Frees the room of one handled frame.
    func release(_ byteCount: Int, from room: Room) {
        condition.lock()
        switch room {
        case .shared:
            unhandledBytes -= byteCount
            unhandledMessages -= 1
        case .reserve:
            reserveIsTaken = false
        }
        condition.broadcast()
        condition.unlock()
    }

    /// Wakes a waiting thread, which then stops reading.
    func close() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }

    private func room(for byteCount: Int, isControl: Bool) -> Room? {
        let sharedIsFull = unhandledMessages >= ConnectionLimits.readAheadMessageLimit
            || (unhandledBytes > 0 && unhandledBytes + byteCount > ConnectionLimits.readAheadByteLimit)
        if !sharedIsFull { return .shared }
        if isControl, byteCount <= ConnectionLimits.controlFrameReserveByteLimit, !reserveIsTaken { return .reserve }
        return nil
    }
}
