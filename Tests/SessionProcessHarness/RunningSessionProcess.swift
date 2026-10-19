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

    /// The login shell of the current user as the directory service reports
    /// it, asked of the `dscl` program. Tests compare the shell of the session
    /// process with this, so that they do not use the code under test as their
    /// own oracle.
    public static func loginShellFromDirectoryService() throws -> String {
        let reader = Process()
        reader.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        reader.arguments = [".", "-read", "/Users/" + NSUserName(), "UserShell"]
        let pipe = Pipe()
        reader.standardOutput = pipe
        reader.standardError = FileHandle.nullDevice
        try reader.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        reader.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard reader.terminationStatus == 0, text.hasPrefix("UserShell:") else {
            throw HarnessError.commandFailed(description: "dscl reported no shell for \(NSUserName()): \(text)")
        }
        return text.dropFirst("UserShell:".count).trimmingCharacters(in: .whitespaces)
    }

    /// Starts the process and waits until it accepts connections.
    ///
    /// - Parameter socketRelativePath: The socket inside the private folder.
    ///   A path with a missing subfolder lets a test see the process create it.
    /// - Parameters:
    ///   - directory: A folder to share with another process. The process that
    ///     gets a folder does not remove it.
    ///   - logName: The file for standard error. Two processes in one folder
    ///     need two names.
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

    /// Runs a test body with a session process, and stops the process after
    /// the body, even when the body throws.
    public static func run<Result: Sendable>(_ body: (RunningSessionProcess) async throws -> Result) async throws -> Result {
        let running = try RunningSessionProcess()
        do {
            let result = try await body(running)
            running.stop()
            return result
        } catch {
            running.stop()
            throw error
        }
    }

    public var processIdentifier: pid_t { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }

    /// What the process wrote to standard error.
    public var log: String {
        (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
    }

    /// Sends a signal to the process.
    public func send(signal: Int32) {
        if process.isRunning { kill(process.processIdentifier, signal) }
    }

    /// Waits for the process to end and returns its exit status, or `nil`
    /// when it is still running after the timeout.
    public func waitForExit(timeout: TimeInterval = 15) async -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return process.isRunning ? nil : process.terminationStatus
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

    /// Runs `openrun` with the arguments and this process's socket.
    public func runCommand(
        _ arguments: [String],
        folder: URL? = nil,
        environment: [String: String] = [:],
        passSocket: Bool = true
    ) throws -> CommandResult {
        try Self.runOpenrun(arguments + (passSocket ? ["--socket", socketPath] : []), folder: folder, environment: environment, in: directory)
    }

    /// Runs `openrun` with the exact arguments.
    public static func runOpenrun(_ arguments: [String], folder: URL? = nil, environment: [String: String] = [:], in directory: URL) throws -> CommandResult {
        let command = Process()
        command.executableURL = commandExecutable
        // Put the options before a "--" separator, where the tool reads them.
        command.arguments = Self.placingOptionsBeforeSeparator(arguments)
        command.currentDirectoryURL = folder ?? directory
        command.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let standardOutput = directory.appendingPathComponent("command-output-\(UUID().uuidString)")
        let standardError = directory.appendingPathComponent("command-error-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: standardOutput.path, contents: nil)
        FileManager.default.createFile(atPath: standardError.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: standardOutput)
        let errorHandle = try FileHandle(forWritingTo: standardError)
        command.standardOutput = outputHandle
        command.standardError = errorHandle
        command.standardInput = FileHandle.nullDevice
        try command.run()

        // A command that hangs must not hang the whole test run.
        let watchdog = DispatchWorkItem { if command.isRunning { kill(command.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        command.waitUntilExit()
        watchdog.cancel()
        try? outputHandle.close()
        try? errorHandle.close()
        let result = CommandResult(
            status: command.terminationStatus,
            standardOutput: (try? String(contentsOf: standardOutput, encoding: .utf8)) ?? "",
            standardError: (try? String(contentsOf: standardError, encoding: .utf8)) ?? ""
        )
        try? FileManager.default.removeItem(at: standardOutput)
        try? FileManager.default.removeItem(at: standardError)
        return result
    }

    private static func placingOptionsBeforeSeparator(_ arguments: [String]) -> [String] {
        // The harness appends "--socket PATH" at the end. After a "--" the
        // tool would read it as part of the program, so move it in front.
        guard let separator = arguments.firstIndex(of: "--"),
              let tail = arguments.lastIndex(of: "--socket"), tail > separator else { return arguments }
        var moved = arguments
        let option = Array(moved[tail...])
        moved.removeSubrange(tail...)
        moved.insert(contentsOf: option, at: separator)
        return moved
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

// What the process holds, as the system reports it. Each value is nil when
// the system call fails, so a test that checks a bound fails instead of
// passing on a value that was never measured.
extension RunningSessionProcess {
    /// The memory that the process uses, in bytes, as Activity Monitor
    /// counts it.
    public var memoryFootprint: Int? {
        guard let usage = resourceUsage else { return nil }
        return Int(usage.ri_phys_footprint)
    }

    /// The processor time that the process has used so far, in user and
    /// system mode together.
    public var processorTime: Duration? {
        guard let usage = resourceUsage else { return nil }
        // The system counts this time in ticks of the machine clock, not in
        // nanoseconds. The time base converts them.
        var timeBase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timeBase) == KERN_SUCCESS, timeBase.denom != 0 else { return nil }
        let ticks = usage.ri_user_time + usage.ri_system_time
        return .nanoseconds(Int64(ticks * UInt64(timeBase.numer) / UInt64(timeBase.denom)))
    }

    /// The number of threads of the process.
    public var threadCount: Int? {
        var information = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDTASKINFO, 0, &information, size) == size else { return nil }
        return Int(information.pti_threadnum)
    }

    /// The number of descriptors that the process has open.
    public var descriptorCount: Int? {
        let estimate = proc_pidinfo(processIdentifier, PROC_PIDLISTFDS, 0, nil, 0)
        guard estimate > 0 else { return nil }
        let entrySize = MemoryLayout<proc_fdinfo>.stride
        var entries = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(estimate) / entrySize + 32)
        let filled = entries.withUnsafeMutableBytes { buffer in
            proc_pidinfo(processIdentifier, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return nil }
        return Int(filled) / entrySize
    }

    private var resourceUsage: rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage : nil
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

// Short forms of the commands that nearly every test uses.
extension RunningSessionProcess {
    /// Starts a session with `openrun new` and returns its identifier.
    public func createSession(
        program: [String] = [],
        folder: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> String {
        var arguments = ["new"]
        if let folder { arguments += ["--folder", folder.path] }
        if !program.isEmpty { arguments += ["--"] + program }
        let result = try runCommand(arguments, environment: environment)
        guard result.status == 0, let identifier = result.outputLines.first else {
            throw HarnessError.commandFailed(arguments: arguments, result: result)
        }
        return identifier
    }

    /// The identifiers that `openrun list` shows. Throws when the command
    /// fails, so a dead session process is not read as an empty list.
    public func listedIdentifiers() throws -> [String] {
        try succeeding(["list"]).outputLines.compactMap { $0.split(separator: "\t").first.map(String.init) }
    }

    /// The text of a session's screen, from `openrun read`. Throws when the
    /// command fails, so a dead session process is not read as an empty screen.
    public func screenText(of identifier: String, includeScrollback: Bool = false) throws -> String {
        try succeeding(["read", identifier] + (includeScrollback ? ["--scrollback"] : [])).standardOutput
    }

    /// Runs a command that must work: status 0 and nothing on standard error.
    private func succeeding(_ arguments: [String]) throws -> CommandResult {
        let result = try runCommand(arguments)
        guard result.status == 0, result.standardError.isEmpty else {
            throw HarnessError.commandFailed(arguments: arguments, result: result)
        }
        return result
    }

    /// Waits until a session's screen shows the text.
    public func waitForScreen(of identifier: String, containing text: String, timeout: Duration = .seconds(15)) async -> Bool {
        await eventually(timeout: timeout) { ((try? screenText(of: identifier)) ?? "").contains(text) }
    }
}
