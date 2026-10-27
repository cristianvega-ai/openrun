/// When the launch agent ends itself: after a time with no session and no
/// client. The next wake starts it again.
///
/// launchd holds the next start for up to 10 seconds after a run that was
/// shorter than 10 seconds, so the time must be longer than that.
struct IdleExit: Sendable {
    static let standardTimeLimit: Duration = .seconds(30)
    /// A setting for tests only, in milliseconds. Only the launch agent
    /// reads it.
    static let testTimeLimitSetting = "OPENRUN_TEST_IDLE_EXIT_MILLISECONDS"

    let timeLimit: Duration

    init(environment: [String: String]) {
        let milliseconds = environment[Self.testTimeLimitSetting].flatMap { Int($0) }
        timeLimit = milliseconds.flatMap { (1...3_600_000).contains($0) ? .milliseconds($0) : nil } ?? Self.standardTimeLimit
    }

    /// Returns once the server has closed its socket for the idle exit, or
    /// when the task is cancelled. `beforeClosing` runs just before the
    /// socket closes.
    func wait(for server: SessionServer, beforeClosing: @escaping @Sendable () -> Void) async {
        // A check each second is enough for 30 seconds. The short limit of
        // a test needs more checks.
        let interval = min(.seconds(1), timeLimit / 4)
        while !Task.isCancelled {
            if await server.closeWhenIdle(for: timeLimit, beforeClosing: beforeClosing) { return }
            try? await Task.sleep(for: interval)
        }
    }
}
