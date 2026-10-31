import Foundation
import Testing
import XPC
@testable import SessionLaunch

/// These tests do not register a launch agent or use the name of the app.
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

    @Test func theFailureMessagesDoNotGuessTheCauseOfATimeout() {
        #expect(SessionWakeFailure.notRegistered.description.contains("Open OpenRun once to register it."))
        #expect(SessionWakeFailure.timedOut(limit: .seconds(15)).description == "The session process did not answer the request to start within 15 seconds.")
    }

    @Test func aWakeReceivesTheSocketPathFromTheService() throws {
        let path = "/a folder/会話/session.socket"
        let service = SessionWakeService(socketPath: path)
        defer { service.cancel() }
        let session = try XPCSession(endpoint: service.endpoint)
        #expect(try SessionWake.wake(session: session, timeLimit: .seconds(2)) == path)
    }

    @Test func aWakeRejectsAnAnswerThatIsNotASocketPath() throws {
        let listener = XPCListener { request in
            request.accept { (_: WakeRequest) -> (any Encodable)? in "not a socket path" }
        }
        defer { listener.cancel() }
        let session = try XPCSession(endpoint: listener.endpoint)
        #expect(throws: SessionWakeFailure.noAnswer(detail: "The answer is not a socket path.")) {
            _ = try SessionWake.wake(session: session, timeLimit: .seconds(2))
        }
    }

    @Test func theCancelledServiceDoesNotAnswerANewWake() throws {
        let service = SessionWakeService(socketPath: "/a/session.socket")
        let endpoint = service.endpoint
        let first = try XPCSession(endpoint: endpoint)
        #expect(try SessionWake.wake(session: first, timeLimit: .seconds(2)) == "/a/session.socket")
        service.cancel()
        var answered = false
        do {
            let next = try XPCSession(endpoint: endpoint)
            _ = try SessionWake.wake(session: next, timeLimit: .seconds(2))
            answered = true
        } catch {}
        #expect(!answered)
    }

    /// A session process that was started by hand gets no Mach service.
    @Test func theWakeServiceDoesNotStartInAProcessThatLaunchdDidNotStart() {
        #expect(throws: (any Error).self) {
            _ = try SessionWakeService(socketPath: "/unused/session.socket", machServiceName: Self.unknownMachServiceName())
        }
    }
}
