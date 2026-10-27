import SessionLaunch
import Testing

@Suite struct LaunchAgentNamesTests {
    /// The owner chose these names on 2026-10-27 (decision D9). Each one is
    /// written out here, so a change to the code does not pass unseen.
    @Test func theNamesAreTheOnesTheOwnerChose() {
        #expect(LaunchAgentNames.applicationBundleIdentifier == "ai.cristianvega.openrun")
        #expect(LaunchAgentNames.label == "ai.cristianvega.openrun.session")
        #expect(LaunchAgentNames.machServiceName == "ai.cristianvega.openrun.session")
        #expect(LaunchAgentNames.propertyListName == "ai.cristianvega.openrun.session.plist")
        #expect(LaunchAgentNames.launchAgentFlag == "--launch-agent")
    }

    @Test func theSettingForTestsChoosesAnotherMachService() {
        let setting = "OPENRUN_TEST_WAKE_SERVICE_NAME"
        #expect(LaunchAgentNames.machServiceName(in: [:]) == "ai.cristianvega.openrun.session")
        #expect(LaunchAgentNames.machServiceName(in: [setting: ""]) == "ai.cristianvega.openrun.session")
        #expect(LaunchAgentNames.machServiceName(in: [setting: "ai.cristianvega.openrun.test.one"]) == "ai.cristianvega.openrun.test.one")
    }
}
