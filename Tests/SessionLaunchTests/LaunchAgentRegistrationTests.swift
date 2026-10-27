import ServiceManagement
@testable import SessionLaunch
import Testing

/// A test cannot register a launch agent, so it checks only how each status
/// of SMAppService reaches the app.
@Suite struct LaunchAgentRegistrationTests {
    @Test func eachStatusOfServiceManagementHasItsOwnValue() throws {
        #expect(LaunchAgentRegistration.status(of: .enabled) == .enabled)
        #expect(LaunchAgentRegistration.status(of: .notRegistered) == .notRegistered)
        #expect(LaunchAgentRegistration.status(of: .requiresApproval) == .requiresApproval)
        #expect(LaunchAgentRegistration.status(of: .notFound) == .notFound)
    }

    @Test func anUnknownStatusNeedsTheUser() throws {
        let unknown = try #require(SMAppService.Status(rawValue: 99))
        #expect(LaunchAgentRegistration.status(of: unknown) == .requiresApproval)
    }
}
