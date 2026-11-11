import PseudoTerminal

/// The rules for the facts of a session that change while its program runs:
/// whether it is in progress, and whether the bell raises an alert
/// (decisions of 2026-11-10). The session gives it each event with its
/// time, on the session's own context.
///
/// A session is in progress while its program writes output, and for
/// `quietTime` after it. It is also in progress while a command runs in the
/// foreground with the terminal in line mode, such as a build that works
/// without output. An agent or an editor reads keys in raw mode, so only its
/// output shows work. A shell at its prompt is not in progress, also right
/// after its own output, such as its prompt or the echo of a key.
struct SessionActivity {
    /// How long a session stays in progress after its last output.
    static let quietTime: Duration = .seconds(2)
    /// A bell this soon after a typed key answers that key, such as a
    /// completion that failed, so it raises no alert.
    static let bellAnswerTime: Duration = .seconds(1)

    /// The program that read the keys at the last look.
    private(set) var foreground: ForegroundState?
    private var lastWorkOutput: ContinuousClock.Instant?
    /// The last output or input of any kind.
    private var lastActivity: ContinuousClock.Instant?
    private var lastTypedKey: ContinuousClock.Instant?

    mutating func noteForeground(_ state: ForegroundState?) {
        foreground = state
    }

    mutating func noteOutput(at now: ContinuousClock.Instant) {
        lastActivity = now
        if !isShellAtItsPrompt { lastWorkOutput = now }
    }

    /// - Parameter isTyped: True for the keys of an attached client, and
    ///   false for text that another program sends.
    mutating func noteInput(at now: ContinuousClock.Instant, isTyped: Bool) {
        lastActivity = now
        if isTyped { lastTypedKey = now }
    }

    func isInProgress(at now: ContinuousClock.Instant) -> Bool {
        if let foreground, foreground.isInLineMode, !isShellAtItsPrompt { return true }
        guard let lastWorkOutput else { return false }
        return now - lastWorkOutput < Self.quietTime
    }

    /// Whether neither output nor input came for `quietTime`, so the facts
    /// need no more looks until the next output or input.
    func isQuiet(at now: ContinuousClock.Instant) -> Bool {
        lastActivity.map { now - $0 >= Self.quietTime } ?? true
    }

    func bellRaisesAlert(at now: ContinuousClock.Instant) -> Bool {
        lastTypedKey.map { now - $0 >= Self.bellAnswerTime } ?? true
    }

    /// The shell that the terminal started, or a shell that reads its keys
    /// in raw mode with its line editor. A shell with a command string or a
    /// script, such as `sh -c` or `bash build.sh`, runs commands.
    private var isShellAtItsPrompt: Bool {
        guard let foreground, InteractiveShell.hasPrompt(foreground.program) else { return false }
        return foreground.leadsSession || !foreground.isInLineMode
    }
}
