import Foundation
import SessionLaunch
import Testing

/// A test cannot register a launch agent, so these tests use Mach service
/// names that launchd does not know, and never the name of the app.
@Suite struct SessionWakeTests {
    private static func unknownMachServiceName() -> String {
        "ai.cristianvega.openrun.test.\(UUID().uuidString)"
    }

    @Test func aWakeForAnUnknownMachServiceFailsAtOnceWithNotRegistered() {
        let start = ContinuousClock.now
        #expect(throws: SessionWakeFailure.notRegistered) {
            _ = try SessionWake.wake(machServiceName: Self.unknownMachServiceName())
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func eachFailureTellsTheUserWhatToDo() {
        #expect(SessionWakeFailure.notRegistered.description.contains("Open OpenRun once to register it."))
        #expect(SessionWakeFailure.timedOut(limit: .seconds(15)).description == "The session process did not answer the request to start within 15 seconds.")
    }

    /// A session process that was started by hand gets no Mach service.
    @Test func theWakeServiceDoesNotStartInAProcessThatLaunchdDidNotStart() {
        #expect(throws: (any Error).self) {
            _ = try SessionWakeService(socketPath: "/unused/session.socket", machServiceName: Self.unknownMachServiceName())
        }
    }
}
