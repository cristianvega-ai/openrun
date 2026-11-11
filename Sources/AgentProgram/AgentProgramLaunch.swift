import Darwin

/// What agent program to run on pipes, and where and how.
public struct AgentProgramLaunch: Equatable, Sendable {
    /// An absolute or relative path, or a bare name to find in `PATH`.
    public var executablePath: String
    /// The arguments after the program name.
    public var arguments: [String]
    /// The working folder.
    public var folder: String
    /// The complete environment. The program inherits nothing else.
    public var environment: [String: String]

    public init(executablePath: String, arguments: [String] = [], folder: String, environment: [String: String]) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.folder = folder
        self.environment = environment
    }

    /// Refuses a value that would reach the program changed, as
    /// `PseudoTerminal` does. A C string ends at its first NUL, so the
    /// program would get a shorter value. The system splits an environment
    /// entry at its first `=`, so a name with `=` would set a variable of
    /// another name. A name that is empty sets no variable at all.
    func checkValues() throws {
        func refuse(_ problem: String) -> AgentProgramError {
            .invalidLaunchValue(problem: problem)
        }
        if executablePath.isEmpty { throw refuse("the program name is empty") }
        if Self.holdsNull(executablePath) { throw refuse("the program name holds a NUL character") }
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

    /// The folder must exist before the program name is looked up. A
    /// relative `PATH` entry is searched inside it, so a missing folder
    /// would otherwise show as a program that cannot be found.
    func checkFolder() throws {
        var information = stat()
        guard stat(folder, &information) == 0 else { throw AgentProgramError.systemCallFailed(function: "chdir", code: errno) }
        guard information.st_mode & S_IFMT == S_IFDIR else { throw AgentProgramError.systemCallFailed(function: "chdir", code: ENOTDIR) }
        guard access(folder, X_OK) == 0 else { throw AgentProgramError.systemCallFailed(function: "chdir", code: errno) }
    }

    /// The file to run. A name with no slash is searched in the `PATH` of
    /// the launch environment, then in the system default. The program
    /// starts in `folder`, so a relative or empty entry means a place
    /// inside that folder, and the result stays relative. Only a regular
    /// file with an execute permission matches.
    func resolvedExecutablePath() throws -> String {
        guard !executablePath.contains("/") else { return executablePath }
        let searchPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
            let candidate = directory.isEmpty ? "./\(executablePath)" : "\(directory)/\(executablePath)"
            let checked = candidate.hasPrefix("/") ? candidate : "\(folder)/\(candidate)"
            var information = stat()
            guard stat(checked, &information) == 0, information.st_mode & S_IFMT == S_IFREG else { continue }
            if access(checked, X_OK) == 0 { return candidate }
        }
        throw AgentProgramError.programNotFound(name: executablePath)
    }
}
