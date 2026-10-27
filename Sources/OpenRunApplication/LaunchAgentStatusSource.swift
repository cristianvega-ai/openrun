import SessionLaunch

/// What the app needs of the registration of the launch agent. Tests use a
/// stand-in, because a test cannot register a launch agent.
protocol LaunchAgentStatusSource: Sendable {
    var status: LaunchAgentStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

extension LaunchAgentRegistration: LaunchAgentStatusSource {}
