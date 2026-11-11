/// What a session shows of the program that reads its keys: the program,
/// where it works, and how the terminal hands it the keys.
public struct ForegroundState: Equatable, Sendable {
    public let program: ForegroundProgram
    /// Whether the program is the one that the terminal started, which
    /// leads the terminal session, such as a shell at its prompt.
    public let leadsSession: Bool
    /// The current folder of the program, or nil when the system does not say.
    public let currentFolder: String?
    /// Whether the terminal is in line mode (`ICANON`), in which the kernel
    /// collects a whole line before a program reads it. A shell runs a
    /// command in line mode. A line editor, an agent or an editor reads
    /// each key in raw mode.
    public let isInLineMode: Bool

    public init(program: ForegroundProgram, leadsSession: Bool, currentFolder: String?, isInLineMode: Bool) {
        self.program = program
        self.leadsSession = leadsSession
        self.currentFolder = currentFolder
        self.isInLineMode = isInLineMode
    }
}
