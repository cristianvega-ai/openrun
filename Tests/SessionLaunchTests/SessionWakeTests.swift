import Foundation
import SessionLaunch
import Testing

/// A test cannot register a launch agent, so these tests use Mach service
/// names that launchd does not know, and never the name of the app.
@Suite struct SessionWakeTests {
    private static func unknownMachServiceName() -> String {
        "ai.cristianvega.openrun.test.\(UUID().uuidString)"
    }

    /// A session process that was started by hand gets no Mach service.
    @Test func theWakeServiceDoesNotStartInAProcessThatLaunchdDidNotStart() {
        #expect(throws: (any Error).self) {
            _ = try SessionWakeService(socketPath: "/unused/session.socket", machServiceName: Self.unknownMachServiceName())
        }
    }
}
