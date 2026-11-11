import Foundation
import SessionProtocol
import Synchronization

/// Stands between the session process and a client that does not read.
/// The session ends a write that takes no byte for 10 seconds, and on a busy
/// Mac a test waited longer than that. While the relay trickles, it moves one
/// byte each 100 ms, so the connection stays and the output still waits in
/// the session. After `flow`, it moves every byte.
final class TrickleRelay: Sendable {
    /// The end that the test reads. It closes when the session closes.
    let connection: MessageConnection
    private let trickles = Mutex(true)

    init(from source: Int32) throws {
        var pair: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw SocketError.connectFailed(code: errno) }
        var enabled: Int32 = 1
        setsockopt(pair[1], SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        connection = MessageConnection(descriptor: pair[0])
        Thread { [self, target = pair[1]] in move(from: source, to: target) }.start()
    }

    func flow() {
        trickles.withLock { $0 = false }
    }

    private func move(from source: Int32, to target: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        moving: while true {
            let trickles = trickles.withLock { $0 }
            let count = recv(source, &chunk, trickles ? 1 : chunk.count, trickles ? MSG_DONTWAIT : 0)
            if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) { break }
            var sent = 0
            while sent < count {
                let written = chunk.withUnsafeBytes { send(target, $0.baseAddress! + sent, count - sent, 0) }
                guard written > 0 else { break moving }
                sent += written
            }
            if trickles { usleep(100_000) }
        }
        close(target)
    }
}
