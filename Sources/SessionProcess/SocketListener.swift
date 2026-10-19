import Darwin
import Dispatch
import Foundation
import SessionProtocol

final class SocketListener: @unchecked Sendable {
    /// Connections in the order they arrived. The stream finishes after `close`.
    let connections: AsyncStream<MessageConnection>
    private let location: SocketLocation
    private let source: DispatchSourceRead

    /// The most accepted connections that may wait for the server to take
    /// them. A connection that waits is outside the client limit and has no
    /// hello deadline yet, so each one would hold a descriptor for nothing.
    /// A connection past the limit is closed at once.
    ///
    /// The server takes each connection at once, but on a busy machine it
    /// can fall behind a burst of clients that connect together. With 16, a
    /// burst of 50 lost most of its clients in a full test run. The limit is
    /// the length of the listen queue, so the process holds no more waiting
    /// connections than the system queues for it before `accept`.
    static let waitingConnectionLimit = Int(listenQueueLength)

    /// The connections that the system queues before `accept`.
    private static let listenQueueLength: Int32 = 64

    init(location: SocketLocation) throws {
        self.location = location
        let descriptor = try Self.bindAndListen(at: location)

        // .bufferingOldest keeps the oldest waiting connections. When the
        // buffer is full, the newest connection is dropped and closes.
        // This is the intended behavior.
        let (stream, continuation) = AsyncStream.makeStream(
            of: MessageConnection.self,
            bufferingPolicy: .bufferingOldest(Self.waitingConnectionLimit)
        )
        connections = stream
        let queue = DispatchQueue(label: "SocketListener")
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        self.source = source
        source.setEventHandler {
            while true {
                let accepted = accept(descriptor, nil, nil)
                if accepted >= 0 {
                    // Some systems pass the non-blocking flag on to accepted
                    // sockets. The connection code expects blocking calls.
                    _ = fcntl(accepted, F_SETFL, 0)
                    let connection = MessageConnection(descriptor: accepted)
                    switch continuation.yield(connection) {
                    case .enqueued:
                        break
                    case .dropped(let dropped):
                        dropped.shutdown()
                    case .terminated:
                        connection.shutdown()
                    @unknown default:
                        connection.shutdown()
                    }
                    continue
                }
                let code = errno
                if code == EINTR || code == ECONNABORTED { continue }
                if code == EAGAIN { return }
                return
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
            continuation.finish()
        }
        source.resume()
    }

    func close() {
        source.cancel()
        unlink(location.path)
    }

    // MARK: - Starting


    private static func bindAndListen(at location: SocketLocation) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SessionProcessError.failure(of: "socket") }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)

        // The file must never exist with wider permissions, even for an
        // instant, so the mask is set before the file is created.
        let previousMask = umask(0o177)
        let bound = location.withAddress { bind(descriptor, $0, $1) }
        let bindError = errno
        umask(previousMask)
        guard bound == 0 else {
            Darwin.close(descriptor)
            // The lock keeps out every session process of this version. An
            // older one without the lock can still bind first.
            if bindError == EADDRINUSE || bindError == EEXIST { throw SessionProcessError.alreadyRunning(path: location.path) }
            throw SessionProcessError.systemCallFailed(function: "bind", code: bindError)
        }
        guard chmod(location.path, 0o600) == 0, listen(descriptor, listenQueueLength) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let failure = SessionProcessError.failure(of: "listen")
            Darwin.close(descriptor)
            unlink(location.path)
            throw failure
        }
        return descriptor
    }
}
