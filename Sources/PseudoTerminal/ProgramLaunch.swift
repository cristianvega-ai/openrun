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
        let program = try resolvedExecutablePath()
        let programString = strdup(program)
        let folderString = strdup(folder)
        let argumentStrings = ([argumentZero] + arguments).map { strdup($0) }
        let environmentStrings = environment.map { strdup("\($0.key)=\($0.value)") }
        let argumentVector = Self.makeVector(of: argumentStrings)
        let environmentVector = Self.makeVector(of: environmentStrings)
        defer {
            free(programString)
            free(folderString)
            argumentStrings.forEach { free($0) }
            environmentStrings.forEach { free($0) }
            argumentVector.deallocate()
            environmentVector.deallocate()
        }

        let child = ChildArguments(
            program: programString!,
            folder: folderString!,
            argumentVector: argumentVector,
            environmentVector: environmentVector,
        )
        var windowSize = winsize(ws_row: size.rows, ws_col: size.columns, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1
        var processIdentifier: pid_t = -1
        processIdentifier = forkpty(&master, nil, nil, &windowSize)
        if processIdentifier == 0 { Self.runChild(child) }
        let forkFailure = PseudoTerminalError.failure(of: "forkpty")
        guard processIdentifier > 0 else { throw forkFailure }

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

    /// Plain pointers and numbers, so the child touches no reference counts.
    private struct ChildArguments {
        var program: UnsafeMutablePointer<CChar>
        var folder: UnsafeMutablePointer<CChar>
        var argumentVector: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        var environmentVector: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    }

    /// Runs in the child, right after `forkpty` made the new session and the
    /// controlling terminal. See `start` for the rules of this function.
    @inline(never)
    private static func runChild(_ child: ChildArguments) -> Never {
        if chdir(child.folder) != 0 { _exit(127) }
        execve(child.program, child.argumentVector, child.environmentVector)
        _exit(127)
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
