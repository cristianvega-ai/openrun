import Darwin

/// What to run in a pseudo terminal, and where and how.
public struct ProgramLaunch: Equatable, Sendable {
    /// An absolute or relative path, or a bare name to find in `PATH`.
    public var executablePath: String
    /// The name the program sees for itself. A login shell starts with a dash.
    public var argumentZero: String
    /// The arguments after the program name.
    public var arguments: [String]
    /// The working folder.
    public var folder: String
    /// The complete environment. The program inherits nothing else.
    public var environment: [String: String]
    /// The first size of the terminal.
    public var size: PseudoTerminalSize

    public init(
        executablePath: String,
        argumentZero: String? = nil,
        arguments: [String] = [],
        folder: String,
        environment: [String: String],
        size: PseudoTerminalSize
    ) {
        self.executablePath = executablePath
        self.argumentZero = argumentZero ?? executablePath
        self.arguments = arguments
        self.folder = folder
        self.environment = environment
        self.size = size
    }
}

/// A program that was started on a new pseudo terminal.
struct StartedProgram {
    var processIdentifier: pid_t
    /// The controlling side of the pseudo terminal. It does not stay open in
    /// other programs, and reading from it never blocks.
    var masterDescriptor: Int32
    var terminalPath: String
}

extension ProgramLaunch {
    /// Starts the program on a new pseudo terminal. The terminal is the
    /// program's standard input, output and error, and its controlling
    /// terminal. The program is the leader of a new session.
    ///
    /// A controlling terminal needs a session leader to open the terminal
    /// device after `setsid`. `posix_spawn` cannot do this: it opens files
    /// before it makes the new session, so the program would start without a
    /// controlling terminal. Control-C would do nothing, and zsh would run
    /// without job control. `forkpty` makes the new session and the
    /// controlling terminal in the child, and then the child starts the
    /// program.
    ///
    /// The child shares the memory state of a process that has other threads,
    /// so it must not allocate or take a lock. Everything it needs is prepared
    /// before the fork, and it calls only system functions with plain numbers
    /// and pointers until `execve` replaces it.
    func start() throws -> StartedProgram {
        try checkValues()
        let program = try resolvedExecutablePath()
        let programString = strdup(program)
        let folderString = strdup(folder)
        let argumentStrings = ([argumentZero] + arguments).map { strdup($0) }
        let environmentStrings = environment.map { strdup("\($0.key)=\($0.value)") }
        // A file that the kernel cannot run and that has no `#!` line fails
        // with ENOEXEC. Shells then run it as a script, and so do we.
        let shellString = strdup(Self.shellPath)
        let shellArgumentStrings = (["sh", "--", program] + arguments).map { strdup($0) }
        let shellArgumentVector = Self.makeVector(of: shellArgumentStrings)
        let argumentVector = Self.makeVector(of: argumentStrings)
        let environmentVector = Self.makeVector(of: environmentStrings)
        defer {
            free(programString)
            free(folderString)
            free(shellString)
            shellArgumentStrings.forEach { free($0) }
            shellArgumentVector.deallocate()
            argumentStrings.forEach { free($0) }
            environmentStrings.forEach { free($0) }
            argumentVector.deallocate()
            environmentVector.deallocate()
        }

        // The child reports a failed step through this pipe. A successful
        // `execve` closes it, so the parent reads nothing.
        var pipeDescriptors: [Int32] = [-1, -1]
        guard pipe(&pipeDescriptors) == 0 else { throw PseudoTerminalError.failure(of: "pipe") }
        let reportReader = pipeDescriptors[0]
        let reportWriter = pipeDescriptors[1]
        _ = fcntl(reportReader, F_SETFD, FD_CLOEXEC)
        _ = fcntl(reportWriter, F_SETFD, FD_CLOEXEC)
        defer { close(reportReader) }

        let child = ChildArguments(
            program: programString!,
            folder: folderString!,
            shell: shellString!,
            shellArgumentVector: shellArgumentVector,
            argumentVector: argumentVector,
            environmentVector: environmentVector,
            reportDescriptor: reportWriter,
            descriptorLimit: min(getdtablesize(), Self.descriptorLimitCeiling)
        )
        var windowSize = winsize(ws_row: size.rows, ws_col: size.columns, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1
        var processIdentifier: pid_t = -1
        // When several threads open pseudo terminals at once, the kernel can
        // fail an open with an internal restart code instead of an error
        // number. The same call succeeds when repeated. Nothing has forked yet
        // when the call fails, so repeating it is safe.
        for _ in 0..<5 {
            processIdentifier = forkpty(&master, nil, nil, &windowSize)
            if processIdentifier == 0 { Self.runChild(child) }
            if processIdentifier > 0 { break }
            if errno > 0 && errno != EAGAIN && errno != EINTR { break }
            usleep(1000)
        }
        let forkFailure = PseudoTerminalError.failure(of: "forkpty")
        close(reportWriter)
        guard processIdentifier > 0 else { throw forkFailure }

        if let failure = Self.readReport(from: reportReader) {
            close(master)
            Self.reap(processIdentifier: processIdentifier)
            throw failure
        }
        // Keep the descriptor out of programs that other threads start, and
        // let reads return at once when no output waits.
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        guard fcntl(master, F_SETFL, O_NONBLOCK) == 0 else {
            let failure = PseudoTerminalError.failure(of: "fcntl")
            close(master)
            kill(processIdentifier, SIGKILL)
            Self.reap(processIdentifier: processIdentifier)
            throw failure
        }
        var nameBuffer = [CChar](repeating: 0, count: 128)
        guard ptsname_r(master, &nameBuffer, nameBuffer.count) == 0 else {
            let failure = PseudoTerminalError.failure(of: "ptsname_r")
            close(master)
            kill(processIdentifier, SIGKILL)
            Self.reap(processIdentifier: processIdentifier)
            throw failure
        }
        let path = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return StartedProgram(processIdentifier: processIdentifier, masterDescriptor: master, terminalPath: path)
    }

    /// Waits for a child that this process started and no longer needs. A
    /// signal can interrupt the wait, so it repeats until the child is gone.
    ///
    /// - Parameter wait: The system call. Tests replace it.
    /// - Returns: Whether the child was reaped.
    @discardableResult
    static func reap(
        processIdentifier: pid_t,
        using wait: (pid_t, UnsafeMutablePointer<Int32>?, Int32) -> pid_t = { waitpid($0, $1, $2) }
    ) -> Bool {
        var status: Int32 = 0
        while true {
            let result = wait(processIdentifier, &status, 0)
            if result == -1 && errno == EINTR { continue }
            return result == processIdentifier
        }
    }

    /// Refuses a value that would reach the program changed. A C string ends
    /// at its first NUL, so the program would get a shorter value, or another
    /// folder. The system splits an environment entry at its first `=`, so a
    /// name with `=` would set a variable of another name, such as one that
    /// OpenRun sets itself. A name that is empty sets no variable at all.
    private func checkValues() throws {
        func refuse(_ problem: String) -> PseudoTerminalError {
            .invalidLaunchValue(problem: problem)
        }
        if Self.holdsNull(executablePath) { throw refuse("the program name holds a NUL character") }
        if Self.holdsNull(argumentZero) { throw refuse("the name the program sees for itself holds a NUL character") }
        if let index = arguments.firstIndex(where: Self.holdsNull) {
            throw refuse("argument \(index + 1) holds a NUL character")
        }
        if Self.holdsNull(folder) { throw refuse("the folder holds a NUL character") }
        // Sorted, so the same environment always gets the same answer.
        for name in environment.keys.sorted() {
            if name.isEmpty { throw refuse("an environment variable has an empty name") }
            if name.utf8.contains(UInt8(ascii: "=")) { throw refuse("an environment variable name holds an equals sign (=)") }
            if Self.holdsNull(name) { throw refuse("an environment variable name holds a NUL character") }
        }
        if environment.values.contains(where: Self.holdsNull) {
            throw refuse("the value of an environment variable holds a NUL character")
        }
    }

    private static func holdsNull(_ text: String) -> Bool {
        text.utf8.contains(0)
    }

    // MARK: - The child

    private static let shellPath = "/bin/sh"

    /// Descriptors above this number are not closed in the child. They were
    /// opened by this process, which marks its own descriptors close-on-exec.
    private static let descriptorLimitCeiling: Int32 = 10_240

    /// The two steps that can fail in the child, as the pipe reports them. An
    /// enumeration needs no lazy set-up, which the child must not trigger.
    private enum ChildStep: Int32 {
        case changeFolder = 1
        case execute = 2
    }

    /// Plain pointers and numbers, so the child touches no reference counts.
    private struct ChildArguments {
        var program: UnsafeMutablePointer<CChar>
        var folder: UnsafeMutablePointer<CChar>
        var shell: UnsafeMutablePointer<CChar>
        var shellArgumentVector: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        var argumentVector: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        var environmentVector: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        var reportDescriptor: Int32
        var descriptorLimit: Int32
    }

    /// Runs in the child, right after `forkpty` made the new session and the
    /// controlling terminal. See `start` for the rules of this function.
    @inline(never)
    private static func runChild(_ child: ChildArguments) -> Never {
        // Lets the line editor of a terminal in cooked mode erase a whole
        // multibyte character with one backspace. Failure only loses that nicety.
        var attributes = termios()
        if tcgetattr(0, &attributes) == 0 {
            attributes.c_iflag |= tcflag_t(IUTF8)
            tcsetattr(0, TCSANOW, &attributes)
        }
        // The session process ignores some signals and blocks others. Both
        // settings survive exec, so the program gets the defaults back.
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        sigprocmask(SIG_SETMASK, &noSignals, nil)
        var number: Int32 = 1
        while number < 32 {
            if number != SIGKILL && number != SIGSTOP { signal(number, SIG_DFL) }
            number += 1
        }
        if chdir(child.folder) != 0 { reportFailure(.changeFolder, errorNumber: errno, to: child.reportDescriptor) }
        // No descriptor of the session process may leak into the program.
        var descriptor: Int32 = 3
        while descriptor < child.descriptorLimit {
            if descriptor != child.reportDescriptor { close(descriptor) }
            descriptor += 1
        }
        execve(child.program, child.argumentVector, child.environmentVector)
        let executeError = errno
        if executeError == ENOEXEC {
            execve(child.shell, child.shellArgumentVector, child.environmentVector)
        }
        // Report the first error: it names the program, not the fallback.
        reportFailure(.execute, errorNumber: executeError, to: child.reportDescriptor)
    }

    private static func reportFailure(_ step: ChildStep, errorNumber: Int32, to descriptor: Int32) -> Never {
        var report: (Int32, Int32) = (step.rawValue, errorNumber)
        write(descriptor, &report, MemoryLayout<(Int32, Int32)>.size)
        _exit(127)
    }

    // MARK: - The parent

    /// The failure that the child reported, or `nil` when the pipe closed
    /// without a report because `execve` worked.
    private static func readReport(from descriptor: Int32) -> PseudoTerminalError? {
        var report: (Int32, Int32) = (0, 0)
        var count = 0
        repeat {
            count = read(descriptor, &report, MemoryLayout<(Int32, Int32)>.size)
        } while count < 0 && errno == EINTR
        guard count == MemoryLayout<(Int32, Int32)>.size else { return nil }
        let function = report.0 == ChildStep.changeFolder.rawValue ? "chdir" : "execve"
        return .systemCallFailed(function: function, code: report.1)
    }

    private static func makeVector(of strings: [UnsafeMutablePointer<CChar>?]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let vector = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for (index, string) in strings.enumerated() { vector[index] = string }
        vector[strings.count] = nil
        return vector
    }

    /// Finds the file to run. A name with no slash is searched in the `PATH`
    /// of the launch environment, then in the system default.
    ///
    /// `execve` runs after `chdir(folder)`, so a relative or empty `PATH`
    /// entry means a place inside the launch folder, not inside the folder of
    /// the session process. The result of such an entry stays relative, so it
    /// names the same file when `execve` uses it. Only a regular file with an
    /// execute permission matches: `access` alone also accepts a folder.
    func resolvedExecutablePath() throws -> String {
        guard !executablePath.contains("/") else { return executablePath }
        let searchPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // Empty entries count: they mean the current folder.
        for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
            let candidate = directory.isEmpty ? "./\(executablePath)" : "\(directory)/\(executablePath)"
            let checked = candidate.hasPrefix("/") ? candidate : "\(folder)/\(candidate)"
            if Self.isExecutableRegularFile(checked) { return candidate }
        }
        throw PseudoTerminalError.programNotFound(name: executablePath)
    }

    private static func isExecutableRegularFile(_ path: String) -> Bool {
        var information = stat()
        guard stat(path, &information) == 0, information.st_mode & S_IFMT == S_IFREG else { return false }
        return access(path, X_OK) == 0
    }
}
