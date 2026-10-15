import Darwin

/// The shell that the user database names for the current user.
public struct LoginShell: Equatable, Sendable {
    /// The absolute path of the shell program.
    public let path: String

    /// Used when the user database names no shell.
    static let fallbackPath = "/bin/zsh"

    public init(path: String) {
        self.path = path
    }

    /// Reads the shell of the current user from the user database.
    public static func current() -> LoginShell {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        let status = getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result)
        guard status == 0, result != nil, let shell = entry.pw_shell, shell.pointee != 0 else {
            return LoginShell(path: fallbackPath)
        }
        return LoginShell(path: String(cString: shell))
    }

    /// The name the shell sees for itself. A leading dash is the convention
    /// that tells a shell to run as a login shell and read the user's profile.
    public var argumentZero: String {
        "-" + (path.split(separator: "/").last.map(String.init) ?? path)
    }

    /// A launch that runs this shell as a login shell.
    public func launch(folder: String, environment: [String: String], size: PseudoTerminalSize) -> ProgramLaunch {
        ProgramLaunch(
            executablePath: path,
            argumentZero: argumentZero,
            arguments: [],
            folder: folder,
            environment: environment,
            size: size
        )
    }
}
