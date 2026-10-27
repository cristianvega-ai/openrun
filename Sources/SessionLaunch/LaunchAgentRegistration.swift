import ServiceManagement

/// The registration of the session process as the launch agent of the app.
///
/// Only the app can use it: SMAppService finds the property list in
/// `Contents/Library/LaunchAgents` of the bundle of the calling program.
public struct LaunchAgentRegistration: Sendable {
    public init() {}

    private var service: SMAppService {
        SMAppService.agent(plistName: LaunchAgentNames.propertyListName)
    }

    public var status: LaunchAgentStatus { Self.status(of: service.status) }

    /// Registers the agent. This starts nothing: launchd starts the session
    /// process at the first wake.
    public func register() throws {
        try service.register()
    }

    /// Removes the registration. launchd stops a session process that runs
    /// with SIGTERM, so every session ends.
    public func unregister() throws {
        try service.unregister()
    }

    /// Opens Login Items in System Settings, where the user allows the agent.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// A status that a later macOS adds counts as one that needs the user,
    /// so the app tells the user and does not register again.
    static func status(of status: SMAppService.Status) -> LaunchAgentStatus {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .requiresApproval
        }
    }
}
