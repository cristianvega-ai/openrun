import Foundation
import SessionLaunch
import Testing

/// launchd starts the session process only when `Bundle/` and the code
/// agree, and a mistake shows only when a client waits for a wake.
@Suite struct LaunchAgentPropertyListTests {
    /// `Tests/SessionLaunchTests/` is two folders below the repository.
    static let bundleFolder = URL(fileURLWithPath: "../../Bundle", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL

    static func propertyList(named name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: bundleFolder.appendingPathComponent(name))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theAgentPropertyListHasTheNamesOfTheCode() throws {
        let agent = try Self.propertyList(named: LaunchAgentNames.propertyListName)
        #expect(agent["Label"] as? String == LaunchAgentNames.label)
        #expect(agent["MachServices"] as? [String: Bool] == [LaunchAgentNames.machServiceName: true])
        #expect(agent["BundleProgram"] as? String == "Contents/MacOS/openrun-session")
        #expect(agent["ProgramArguments"] as? [String] == ["openrun-session", LaunchAgentNames.launchAgentFlag])
        #expect(agent["AssociatedBundleIdentifiers"] as? [String] == [LaunchAgentNames.applicationBundleIdentifier])
    }

    /// Decisions D5 and D6 of 2026-10-27. With no other key, nothing starts
    /// the agent at login or at load.
    @Test func launchdRestartsTheAgentOnlyAfterACrash() throws {
        let agent = try Self.propertyList(named: LaunchAgentNames.propertyListName)
        #expect(agent["KeepAlive"] as? [String: Bool] == ["Crashed": true])
        #expect(agent["ProcessType"] as? String == "Interactive")
        #expect(Set(agent.keys) == ["Label", "BundleProgram", "ProgramArguments", "MachServices", "KeepAlive", "ProcessType", "AssociatedBundleIdentifiers"])
    }

    /// The bundle script installs `openrun-application` as `OpenRun` (D7).
    @Test func theAppPropertyListNamesTheBundleAndItsProgram() throws {
        let application = try Self.propertyList(named: "Info.plist")
        #expect(application["CFBundleIdentifier"] as? String == LaunchAgentNames.applicationBundleIdentifier)
        #expect(application["CFBundleExecutable"] as? String == "OpenRun")
        #expect(application["CFBundlePackageType"] as? String == "APPL")
        #expect(application["LSMinimumSystemVersion"] as? String == "26.0")
        #expect(application["NSPrincipalClass"] as? String == "NSApplication")
    }
}
