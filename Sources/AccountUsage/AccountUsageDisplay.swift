/// The usage of one account of an agent, as the first pane shows it
/// (decision of 2026-10-15): each window of its limit, and when the
/// reading came, because a reading can be old (proposal 7).
public struct AccountUsageDisplay: Equatable, Sendable {
    /// One window of the limit, such as the week.
    public struct Window: Equatable, Sendable {
        public var name: String
        /// The used part of the window, from 0 to 1.
        public var usedFraction: Double
        public var isAtLimit: Bool

        public init(name: String, usedFraction: Double, isAtLimit: Bool = false) {
            (self.name, self.usedFraction, self.isAtLimit) = (name, usedFraction, isAtLimit)
        }
    }

    /// The agent and the account, such as "Claude Code" or "Codex · Work".
    public var title: String
    public var windows: [Window]
    /// The time of the reading, such as "14:32", or its day, such as
    /// "Nov 12", for a reading of an earlier day.
    public var readTime: String
    /// The whole reading in words, with the reset times.
    public var help: String
    /// The agent as the session process names it, and the name of the
    /// account, or `nil` for the account of the login shell.
    public var agent: String
    public var account: String?

    public init(title: String, windows: [Window], readTime: String, help: String, agent: String = "", account: String? = nil) {
        (self.title, self.windows, self.readTime, self.help, self.agent, self.account) = (title, windows, readTime, help, agent, account)
    }
}
