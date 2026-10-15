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

extension ProgramLaunch {

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
