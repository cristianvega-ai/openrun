import Darwin
import Foundation
import Synchronization

/// Tools for the tests of the socket's security and of how a session process
/// starts: a session process started as a person starts it, programs that
/// stand on the socket path in place of a session process, and the lock of
/// the socket.
public enum SocketSecurityHarness {
    /// A new folder under `TMPDIR` with exactly this mode. The mode is set
    /// after the folder exists, so the umask does not change it.
    public static func makeFolder(mode: mode_t) throws -> URL {
        let folder = try RunningSessionProcess.makeDirectory()
        guard chmod(folder.path, mode) == 0 else { throw HarnessError.commandFailed(description: "chmod \(folder.path) failed: \(errno)") }
        return folder
    }

    /// Adds an entry to the access control list of a file or folder, such as
    /// "everyone allow add_file", with `chmod +a`.
    public static func addAccessControlEntry(_ entry: String, to path: String) throws {
        let status = try changeMode(["+a", entry, path])
        guard status == 0 else { throw HarnessError.commandFailed(description: "chmod +a '\(entry)' \(path) exited \(status)") }
    }

    /// Removes every entry of the access control list of a folder and of all
    /// that it holds, so that a deny entry cannot keep it from being removed.
    public static func removeAccessControlLists(under path: String) {
        _ = try? changeMode(["-R", "-N", path])
    }

    private static func changeMode(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// The mode bits of a file or folder, or nil when it does not exist.
    public static func mode(of path: String) -> mode_t? {
        var status = stat()
        guard stat(path, &status) == 0 else { return nil }
        return status.st_mode & 0o7777
    }

    /// The device and inode of the file at the path itself, without following
    /// a symbolic link, or nil when there is none. Two values differ when the
    /// file was replaced.
    public static func fileIdentity(at path: String) -> FileIdentity? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return FileIdentity(device: status.st_dev, serialNumber: status.st_ino)
    }

    public struct FileIdentity: Equatable, Sendable {
        public let device: dev_t
        public let serialNumber: ino_t
    }

    /// The lock file that a session process holds next to its socket.
    public static func lockPath(forSocket socketPath: String) -> String {
        socketPath + ".lock"
    }

    /// Takes the lock of a socket, as a session process holds it from the
    /// start. Returns the descriptor, or nil when another process
    /// holds the lock. Close the descriptor to release it.
    public static func takeSocketLock(forSocket socketPath: String) -> Int32? {
        let descriptor = open(lockPath(forSocket: socketPath), O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    /// Starts `count` session processes on one socket at the same moment. Each
    /// starts as a shell that waits on one pipe and then replaces itself with
    /// `openrun-session`, so the process identifiers stay. One write to the
    /// pipe releases all of them.
    public static func startTogether(count: Int, socketPath: String, folder: URL) throws -> [StartedSessionProcess] {
        let gate = folder.appendingPathComponent("gate-\(UInt32.random(in: 0...UInt32.max))")
        guard mkfifo(gate.path, 0o600) == 0 else { throw HarnessError.commandFailed(description: "mkfifo failed: \(errno)") }
        defer { unlink(gate.path) }
        // Read and write, so the open does not wait for a reader, and the
        // bytes stay in the pipe for a shell that opens it late.
        let gateDescriptor = open(gate.path, O_RDWR | O_CLOEXEC)
        guard gateDescriptor >= 0 else { throw HarnessError.commandFailed(description: "open of the gate failed: \(errno)") }
        defer { close(gateDescriptor) }
        var started: [StartedSessionProcess] = []
        for index in 0..<count {
            started.append(try StartedSessionProcess(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "read line < \"$1\"; exec \"$2\" --socket \"$3\"", "sh", gate.path, RunningSessionProcess.sessionExecutable.path, socketPath],
                folder: folder,
                logFile: folder.appendingPathComponent("log-\(index)")
            ))
        }
        let release = Array(String(repeating: "go\n", count: count).utf8)
        guard write(gateDescriptor, release, release.count) == release.count else {
            for process in started { process.stop() }
            throw HarnessError.commandFailed(description: "write to the gate failed: \(errno)")
        }
        // Each shell reads its own line. Keep the pipe open until every shell
        // has read, so none of them waits for a writer that has gone.
        let deadline = Date().addingTimeInterval(10)
        repeat {
            var entry = pollfd(fd: gateDescriptor, events: Int16(POLLIN), revents: 0)
            if poll(&entry, 1, 0) == 0 { break }
            usleep(2_000)
        } while Date() < deadline
        return started
    }
}

extension SocketSecurityHarness {
    /// `openrun-session`, or a shell that becomes it, with exact arguments in
    /// a given folder. It ends by process identifier only.
    public final class StartedSessionProcess: @unchecked Sendable {
        private let process = Process()
        public let logFile: URL

        public convenience init(arguments: [String], folder: URL, logFile: URL, environment: [String: String] = [:]) throws {
            try self.init(executable: RunningSessionProcess.sessionExecutable, arguments: arguments, folder: folder, logFile: logFile, environment: environment)
        }

        public init(executable: URL, arguments: [String], folder: URL, logFile: URL, environment: [String: String] = [:]) throws {
            self.logFile = logFile
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = folder
            // The socket comes from the arguments or from `environment`, never
            // from the environment of the test run.
            var inherited = ProcessInfo.processInfo.environment
            inherited["OPENRUN_SOCKET"] = nil
            process.environment = inherited.merging(environment) { _, new in new }
            let log = try FileHandle(forWritingTo: logFile)
            process.standardError = log
            process.standardOutput = log
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }

        public var processIdentifier: pid_t { process.processIdentifier }
        public var isRunning: Bool { process.isRunning }

        public var log: String {
            (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        }

        /// The exit status, or nil when the process still runs after the timeout.
        public func waitForExit(timeout: TimeInterval = 15) async -> Int32? {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            return process.isRunning ? nil : process.terminationStatus
        }

        /// Waits until the log holds the text, or the process ends, or the
        /// timeout passes. Returns whether the log holds the text.
        public func waitForLog(containing text: String, timeout: TimeInterval = 15) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if log.contains(text) { return true }
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return log.contains(text)
        }

        public func send(signal: Int32) {
            if process.isRunning { kill(process.processIdentifier, signal) }
        }

        /// SIGTERM, then SIGKILL after 10 seconds.
        public func stop() {
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGTERM)
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning, Date() < deadline { usleep(20_000) }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
    }
}

extension SocketSecurityHarness {
    /// A program of the same user that is not a session process and sits on
    /// the socket path, as a squatter or a hung program would. It counts what
    /// reaches it.
    public final class StandInListener: @unchecked Sendable {
        public enum Behavior: Sendable {
            /// Binds the path and never listens, as a session process does for
            /// a moment while it starts.
            case boundOnly
            /// Accepts connections and never writes a byte.
            case neverAnswers
            /// Accepts connections and writes these bytes once the first bytes
            /// arrive, then reads all that follows. It closes a connection that
            /// stays quiet for half a second after the answer, so a client that
            /// waits for more fails soon instead of hanging. A test passes the
            /// frame of a hello, so the stand-in passes for a session process.
            case answers(Data)
        }

        public let path: String
        private let descriptor: Int32
        private let counts = Mutex((accepted: 0, received: 0))
        private let accepted = Mutex<[Int32]>([])
        private let stopped = Atomic<Bool>(false)

        public init(path: String, behavior: Behavior) throws {
            self.path = path
            descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw HarnessError.commandFailed(description: "socket failed: \(errno)") }
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8.prefix($0.count - 1)) }
            let length = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
            }
            guard bound == 0 else {
                let code = errno
                Darwin.close(descriptor)
                throw HarnessError.commandFailed(description: "bind \(path) failed: \(code)")
            }
            if case .boundOnly = behavior { return }
            guard listen(descriptor, 16) == 0 else {
                let code = errno
                Darwin.close(descriptor)
                throw HarnessError.commandFailed(description: "listen failed: \(code)")
            }
            let thread = Thread { [self] in serve(behavior) }
            thread.name = "StandInListener"
            thread.start()
        }

        /// The connections that the stand-in accepted.
        public var acceptedCount: Int { counts.withLock { $0.accepted } }
        /// The bytes that clients sent to it.
        public var receivedByteCount: Int { counts.withLock { $0.received } }

        /// Stops accepting and closes every connection. The socket file stays.
        public func close() {
            guard !stopped.exchange(true, ordering: .sequentiallyConsistent) else { return }
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            for connection in accepted.withLock({ $0 }) { Darwin.shutdown(connection, SHUT_RDWR) }
        }

        private func serve(_ behavior: Behavior) {
            while !stopped.load(ordering: .sequentiallyConsistent) {
                var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                guard poll(&entry, 1, 50) > 0 else { continue }
                let connection = accept(descriptor, nil, nil)
                guard connection >= 0 else { continue }
                counts.withLock { $0.accepted += 1 }
                accepted.withLock { $0.append(connection) }
                let reader = Thread { [self] in read(from: connection, behavior) }
                reader.start()
            }
        }

        private func read(from connection: Int32, _ behavior: Behavior) {
            defer { Darwin.close(connection) }
            var answeredAt: Date?
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while !stopped.load(ordering: .sequentiallyConsistent) {
                var entry = pollfd(fd: connection, events: Int16(POLLIN), revents: 0)
                guard poll(&entry, 1, 50) > 0 else {
                    if let answeredAt, Date().timeIntervalSince(answeredAt) > 0.5 { return }
                    continue
                }
                let count = Darwin.read(connection, &buffer, buffer.count)
                guard count > 0 else { return }
                counts.withLock { $0.received += count }
                if case .answers(let answer) = behavior {
                    if answeredAt == nil {
                        _ = answer.withUnsafeBytes { Darwin.send(connection, $0.baseAddress, $0.count, MSG_NOSIGNAL) }
                    }
                    answeredAt = Date()
                }
            }
        }
    }
}
