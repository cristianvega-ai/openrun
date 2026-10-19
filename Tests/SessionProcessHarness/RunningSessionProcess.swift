import Darwin
import Foundation

/// A real `openrun-session` process on a socket in a private folder, for
/// integration tests. The folder lives under `TMPDIR`, because a Unix socket
/// path must stay short.
public final class RunningSessionProcess: @unchecked Sendable {
    public let directory: URL
    public let socketPath: String
    private let process = Process()
    private let logFile: URL
    private let ownsDirectory: Bool

    /// Where the products of the build are: the folder that holds the test
    /// bundle also holds the executables that the tests depend on.
    public static let productsDirectory: URL = {
        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        // swift test runs the bundle from a helper process in some versions.
        for argument in CommandLine.arguments where argument.contains(".xctest") {
            if let range = argument.range(of: ".xctest") {
                return URL(fileURLWithPath: String(argument[..<range.upperBound])).deletingLastPathComponent()
            }
        }
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }()

    public static var sessionExecutable: URL { productsDirectory.appendingPathComponent("openrun-session") }
    public static var commandExecutable: URL { productsDirectory.appendingPathComponent("openrun") }

    /// A new private folder with a short name under `TMPDIR`. The system
    /// makes the name and refuses one that exists, so two calls never share a
    /// folder, also when an earlier run left one behind.
    public static func makeDirectory() throws -> URL {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        var template = Array((base as NSString).appendingPathComponent("test-" + String(repeating: "X", count: 6)).utf8CString)
        guard mkdtemp(&template) != nil else {
            throw HarnessError.commandFailed(description: "A folder under \(base) cannot be made: \(String(cString: strerror(errno)))")
        }
        let path = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public init(
        directory: URL? = nil,
        socketRelativePath: String = "socket",
        logName: String = "log",
        waitUntilReady: Bool = true,
        readyTimeout: TimeInterval = 15,
        didStart: (pid_t) -> Void = { _ in }
    ) throws {
        ownsDirectory = directory == nil
        self.directory = try directory ?? Self.makeDirectory()
        socketPath = self.directory.appendingPathComponent(socketRelativePath).path
        logFile = self.directory.appendingPathComponent(logName)
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        process.executableURL = Self.sessionExecutable
        process.arguments = ["--socket", socketPath]
        process.standardError = try FileHandle(forWritingTo: logFile)
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        didStart(process.processIdentifier)
        if waitUntilReady {
            do {
                try waitForSocket(timeout: readyTimeout)
            } catch {
                // The caller gets no object to stop, so a process that stays
                // would outlive the test run, with its session programs.
                stop()
                throw error
            }
        }
    }

    /// What the process wrote to standard error.
    public var log: String {
        (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
    }

    /// Ends the process with SIGTERM, then SIGKILL, and removes the folder.
    public func stop() {
        if process.isRunning {
            kill(process.processIdentifier, SIGTERM)
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning, Date() < deadline { usleep(20_000) }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        if ownsDirectory { try? FileManager.default.removeItem(at: directory) }
    }

    private func waitForSocket(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning {
                throw HarnessError.processEnded(log: log)
            }
            if canConnect() { return }
            usleep(20_000)
        }
        throw HarnessError.socketNotReady(log: log)
    }

    private func canConnect() -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: socketPath.utf8.prefix($0.count - 1)) }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) == 0 }
        }
    }
}

/// Polls until the condition holds or the timeout passes.
public func eventually(timeout: Duration = .seconds(15), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return try await condition()
}
