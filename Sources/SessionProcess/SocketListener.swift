import Darwin
import Dispatch
import Foundation
import SessionProtocol

/// Owns the listening socket: it checks that no other session process runs,
/// creates the socket file with private permissions, and accepts connections
/// from programs of the same user.
final class SocketListener: @unchecked Sendable {
    /// Connections in the order they arrived. The stream finishes after `close`.
    let connections: AsyncStream<MessageConnection>
    private let location: SocketLocation
    private let source: DispatchSourceRead
    /// Held until the listener goes away, which is the end of the process.
    private let lock: SocketLock
    /// The socket file this listener created. `close` removes only this one.
    private let socketFile: (device: dev_t, serialNumber: ino_t)

    /// How long a program that listens on the path may take to answer hello
    /// before it counts as no session process. A live one answers at once.
    static let liveAnswerTimeLimit: Duration = .seconds(2)

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

    /// - Parameter allowedPeer: The user that clients must run as. Tests pass
    ///   another user, because they cannot start a program as one.
    init(location: SocketLocation, allowedPeer: PeerIdentity = .currentUser) throws {
        self.location = location
        try Self.prepareFolder(for: location)
        lock = try SocketLock(socketPath: location.path)
        try Self.removeStaleSocket(at: location)
        let descriptor = try Self.bindAndListen(at: location)
        var status = stat()
        guard lstat(location.path, &status) == 0 else {
            let failure = SessionProcessError.failure(of: "lstat")
            Darwin.close(descriptor)
            throw failure
        }
        socketFile = (status.st_dev, status.st_ino)

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
        let parts = ConnectionLimits.acceptRetryPause.components
        let pause = DispatchTimeInterval.nanoseconds(Int(parts.seconds) * 1_000_000_000 + Int(parts.attoseconds / 1_000_000_000))
        source.setEventHandler { [weak source] in
            while true {
                let accepted = accept(descriptor, nil, nil)
                if accepted >= 0 {
                    // Some systems pass the non-blocking flag on to accepted
                    // sockets. The connection code expects blocking calls.
                    _ = fcntl(accepted, F_SETFL, 0)
                    let connection = MessageConnection(descriptor: accepted)
                    // Another user gets nothing, not even a refusal. Closing
                    // the connection is all it learns.
                    do {
                        try connection.requirePeer(allowedPeer)
                    } catch {
                        SessionServer.log("Refused a connection: \(error)")
                        connection.shutdown()
                        continue
                    }
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
                // Out of descriptors (EMFILE, ENFILE) or memory. A waiting
                // connection keeps the socket ready, so the handler would run
                // again at once. Pause, and let clients leave first.
                guard let source else { return }
                source.suspend()
                queue.asyncAfter(deadline: .now() + pause) { source.resume() }
                return
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
            continuation.finish()
        }
        source.resume()
    }

    /// Stops accepting and removes the socket file, so that no new client can
    /// find the session process. A file that another program put at the path
    /// stays. The lock stays held until the process ends.
    func close() {
        source.cancel()
        var status = stat()
        if lstat(location.path, &status) == 0, status.st_dev == socketFile.device, status.st_ino == socketFile.serialNumber {
            unlink(location.path)
        }
    }

    // MARK: - Starting

    // The socket file is the only door into the session process, and every
    // program of the user can talk to it. A folder that another user can
    // change would let that user put a socket of their own in its place.
    private static func prepareFolder(for location: SocketLocation) throws {
        let folder = location.folder
        var status = stat()
        if stat(folder, &status) != 0 {
            do {
                try FileManager.default.createDirectory(
                    atPath: folder,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw SessionProcessError.failure(of: "mkdir")
            }
        } else if location.isDefault, status.st_uid == geteuid(), (status.st_mode & S_IFMT) == S_IFDIR {
            // This folder belongs to OpenRun, so its mode is ours to fix. A
            // folder chosen with --socket keeps its mode and must pass the
            // check below as it is.
            guard chmod(folder, 0o700) == 0 else { throw SessionProcessError.failure(of: "chmod") }
        }
        try location.checkFolder()
    }

    // A crashed session process leaves its socket file behind. This process
    // holds the lock, so no other session process of this version is alive
    // on the path. What listens there may still be an older session process,
    // or another program. Only a program that answers hello is a session
    // process. A listener that does not answer, or no listener at all, makes
    // the file stale.
    //
    // The check takes up to two seconds, and another program can replace the
    // file meanwhile. Only the socket that was checked is removed.
    private static func removeStaleSocket(at location: SocketLocation) throws {
        var status = stat()
        guard lstat(location.path, &status) == 0 else { return }
        guard (status.st_mode & S_IFMT) == S_IFSOCK else {
            throw SessionProcessError.pathIsNotASocket(path: location.path)
        }
        let checked = (device: status.st_dev, serialNumber: status.st_ino)
        do {
            let connection = try MessageConnection.connect(to: location)
            defer { connection.shutdown() }
            try connection.greetSessionProcess(within: liveAnswerTimeLimit)
            throw SessionProcessError.alreadyRunning(path: location.path)
        } catch SessionProtocolError.systemCallFailed("connect", let code) where code == ECONNREFUSED || code == ENOENT {
            // Nothing listens: the file is stale.
        } catch SessionProtocolError.incompatibleVersion, SessionProtocolError.refused {
            // A session process of another version, or one that serves as
            // many clients as it may. It is alive either way.
            throw SessionProcessError.alreadyRunning(path: location.path)
        } catch let error as SessionProtocolError {
            switch error {
            case .socketFolderOfAnotherUser, .socketFolderWritableByOthers, .socketFolderWritableThroughAccessControlList,
                 .socketFolderIsNotADirectory, .peerIsAnotherUser:
                throw error
            default:
                SessionServer.log("A program listened on \(location.path) and did not answer as a session process (\(error)). Its socket file is replaced.")
            }
        }
        var current = stat()
        // A file that went away leaves nothing to remove.
        guard lstat(location.path, &current) == 0 else { return }
        guard current.st_dev == checked.device, current.st_ino == checked.serialNumber,
              (current.st_mode & S_IFMT) == S_IFSOCK else {
            throw SessionProcessError.socketFileReplaced(path: location.path)
        }
        unlink(location.path)
    }

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

extension SocketListener {
    /// A lock file next to the socket, which a session process holds for its
    /// whole life.
    ///
    /// Checking for a live session process and then creating the socket are
    /// two steps. Two processes that start together could both pass the
    /// check, and the one that lost could remove the other's socket. The lock
    /// makes the two steps one: a process that cannot take it at once refuses
    /// to start.
    ///
    /// The file stays after the process ends. A lock on a file that someone
    /// removes protects nothing, so the file is never removed, and a process
    /// checks that the file it locked is still the one at the path.
    final class SocketLock: Sendable {
        let path: String
        private let descriptor: Int32

        /// Takes the lock for the socket at `socketPath`.
        ///
        /// - Parameter owner: The user that the lock file must belong to.
        ///   Tests pass another user, because they cannot make a file of one.
        /// - Throws: `SessionProcessError.alreadyRunning` when another session
        ///   process holds it, `SessionProcessError.lockFileIsNotARegularFile`
        ///   or `SessionProcessError.lockFileOfAnotherUser`.
        init(socketPath: String, owner: uid_t = geteuid()) throws {
            path = Self.path(forSocket: socketPath)
            descriptor = try Self.take(path, socketPath: socketPath, owner: owner)
        }

        deinit {
            // Closing the descriptor releases the lock. The system releases
            // it also when the process ends in any other way.
            Darwin.close(descriptor)
        }

        static func path(forSocket socketPath: String) -> String {
            socketPath + ".lock"
        }

        private static func take(_ path: String, socketPath: String, owner: uid_t) throws -> Int32 {
            // Each pass that fails found a file that was removed or replaced
            // while it took the lock. That needs another program at work in
            // the folder.
            for _ in 0..<8 {
                // The open neither follows a symbolic link nor waits for the
                // writer of a named pipe. Both are refused below.
                let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
                guard descriptor >= 0 else {
                    let code = errno
                    var status = stat()
                    if lstat(path, &status) == 0, (status.st_mode & S_IFMT) != S_IFREG {
                        throw SessionProcessError.lockFileIsNotARegularFile(path: path)
                    }
                    throw SessionProcessError.systemCallFailed(function: "open \(path)", code: code)
                }
                do {
                    try makePrivate(descriptor, path: path, owner: owner)
                } catch {
                    Darwin.close(descriptor)
                    throw error
                }
                guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                    let code = errno
                    Darwin.close(descriptor)
                    if code == EWOULDBLOCK { throw SessionProcessError.alreadyRunning(path: socketPath) }
                    throw SessionProcessError.systemCallFailed(function: "flock", code: code)
                }
                var locked = stat()
                var current = stat()
                if fstat(descriptor, &locked) == 0, lstat(path, &current) == 0,
                   locked.st_dev == current.st_dev, locked.st_ino == current.st_ino {
                    return descriptor
                }
                Darwin.close(descriptor)
            }
            throw SessionProcessError.lockFileKeepsChanging(path: path)
        }

        // A lock file that was there before may have been made by anyone, in
        // any mode. Another user who can open it can hold the lock, and then
        // no session process starts. Only a regular file of the owner is
        // used, and only the owner may open it.
        private static func makePrivate(_ descriptor: Int32, path: String, owner: uid_t) throws {
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw SessionProcessError.failure(of: "fstat \(path)") }
            guard (status.st_mode & S_IFMT) == S_IFREG else {
                throw SessionProcessError.lockFileIsNotARegularFile(path: path)
            }
            guard status.st_uid == owner else {
                throw SessionProcessError.lockFileOfAnotherUser(path: path, owner: status.st_uid)
            }
            if status.st_mode & 0o7777 != 0o600, fchmod(descriptor, 0o600) != 0 {
                throw SessionProcessError.failure(of: "chmod \(path)")
            }
        }
    }
}
