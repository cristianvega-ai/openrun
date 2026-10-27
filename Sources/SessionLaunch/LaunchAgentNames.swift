/// The names that the property list of the launch agent and the code share.
///
/// The property list is `Bundle/ai.cristianvega.openrun.session.plist`. A
/// test compares it with these names, because launchd starts the program
/// only when both agree.
public enum LaunchAgentNames {
    /// The bundle identifier of OpenRun.app.
    public static let applicationBundleIdentifier = "ai.cristianvega.openrun"
    /// The launchd label of the session process.
    public static let label = "ai.cristianvega.openrun.session"
    /// The Mach service that launchd holds for the agent. A message to it
    /// starts the session process.
    public static let machServiceName = "ai.cristianvega.openrun.session"
    /// The file in `Contents/Library/LaunchAgents` of the app that
    /// `SMAppService.agent(plistName:)` takes.
    public static let propertyListName = "ai.cristianvega.openrun.session.plist"
    /// The argument that the property list gives the session process, so it
    /// knows that launchd started it.
    public static let launchAgentFlag = "--launch-agent"

    /// A setting for tests and for the manual check of the launch agent. It
    /// names another Mach service, so they never touch the service of the
    /// app that the owner uses.
    public static let testMachServiceSetting = "OPENRUN_TEST_WAKE_SERVICE_NAME"

    /// The Mach service of the setting for tests, or `machServiceName`.
    public static func machServiceName(in environment: [String: String]) -> String {
        guard let name = environment[testMachServiceSetting], !name.isEmpty else { return machServiceName }
        return name
    }
}
