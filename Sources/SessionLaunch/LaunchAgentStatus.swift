/// The registration of the launch agent, as SMAppService reports it.
public enum LaunchAgentStatus: Equatable, Sendable {
    /// Registered and allowed to run. launchd can still refuse the program,
    /// as after a build that changed its code signature. Only a wake shows
    /// that the agent starts.
    case enabled
    /// Not registered, or registered and then removed.
    case notRegistered
    /// Registered, and the user must allow it in System Settings, or the
    /// user turned it off there.
    case requiresApproval
    /// SMAppService found no such agent. This is the status before the
    /// first registration.
    case notFound
}
