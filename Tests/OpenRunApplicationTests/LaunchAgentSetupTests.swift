@testable import OpenRunApplication
import SessionLaunch
import Synchronization
import Testing

/// A stand-in for SMAppService, because a test cannot register an agent.
private final class StandInRegistration: LaunchAgentStatusSource {
    private struct Fault: Error, CustomStringConvertible {
        let call: String
        var description: String { "The \(call) call failed." }
    }

    private let state: Mutex<(status: LaunchAgentStatus, afterRegistration: LaunchAgentStatus, calls: [String], failingCall: String?)>

    /// - Parameter failingCall: The call that throws, "register" or "unregister".
    init(_ status: LaunchAgentStatus, afterRegistration: LaunchAgentStatus = .enabled, failingCall: String? = nil) {
        state = Mutex((status, afterRegistration, [], failingCall))
    }

    /// The calls of the setup to the registration, and each connection, in order.
    var events: [String] { state.withLock { $0.calls } }
    var calls: [String] { events.filter { $0 != "connect" } }
    var status: LaunchAgentStatus { state.withLock { $0.status } }
    func record(_ call: String) { state.withLock { $0.calls.append(call) } }
    func register() throws {
        try state.withLock {
            $0.calls.append("register")
            if $0.failingCall == "register" { throw Fault(call: "register") }
            $0.status = $0.afterRegistration
        }
    }
    func unregister() throws {
        try state.withLock {
            $0.calls.append("unregister")
            if $0.failingCall == "unregister" { throw Fault(call: "unregister") }
            $0.status = .notRegistered
        }
    }
    func openSystemSettings() { state.withLock { $0.calls.append("openSystemSettings") } }
}

/// Runs the setup. The connections fail with the failures in order, and
/// the user gives the answers in order. Returns what the setup asked and
/// how often it connected. The events of the registration show the order
/// of the calls and the connections.
private func runSetup(_ registration: StandInRegistration, failures: [SessionWakeFailure?] = [nil], answers: [Bool] = [], registersAgain: Bool = false)
    -> (outcome: LaunchAgentSetup.Outcome, questions: [LaunchAgentQuestion], connections: Int) {
    let record = Mutex((questions: [LaunchAgentQuestion](), connections: 0))
    let setup = LaunchAgentSetup(
        source: registration,
        connect: { () throws(SessionWakeFailure) in
            let index = record.withLock { $0.connections += 1; return $0.connections - 1 }
            registration.record("connect")
            if let failure = failures[min(index, failures.count - 1)] { throw failure }
        },
        ask: { question in
            record.withLock { $0.questions.append(question); return answers.count >= $0.questions.count && answers[$0.questions.count - 1] }
        }
    )
    let outcome = registersAgain ? setup.registerAgain() : setup.run()
    return record.withLock { (outcome, $0.questions, $0.connections) }
}

@Suite(.serialized) struct LaunchAgentSetupTests {
    private enum ConnectionFault: Error, CustomStringConvertible {
        case closed
        var description: String { "The connection closed." }
    }

    @Test func aConnectionErrorThatIsNotAWakeFailureIsShown() {
        let registration = StandInRegistration(.enabled)
        let questions = Mutex<[LaunchAgentQuestion]>([])
        let setup = LaunchAgentSetup(
            source: registration, connect: { throw ConnectionFault.closed },
            ask: { question in questions.withLock { $0.append(question) }; return false })
        #expect(setup.run() == .failed)
        #expect(questions.withLock { $0 } == [.failed(detail: "The connection closed.")])
    }
    @Test func anEnabledAgentThatStartsNeedsNothing() {
        let registration = StandInRegistration(.enabled)
        let result = runSetup(registration)
        #expect(result.outcome == .ready && result.questions.isEmpty && result.connections == 1)
        #expect(registration.calls.isEmpty)
    }

    /// The status is `notFound` before the first registration of a bundle.
    @Test(arguments: [LaunchAgentStatus.notRegistered, .notFound])
    func anAgentThatIsNotRegisteredIsRegisteredOnce(status: LaunchAgentStatus) {
        let registration = StandInRegistration(status)
        let result = runSetup(registration)
        #expect(result.outcome == .ready && result.questions.isEmpty && result.connections == 1)
        #expect(registration.calls == ["register"])
    }

    @Test(arguments: [false, true])
    func anAgentThatNeedsApprovalIsNotRegisteredAgain(userOpensSystemSettings: Bool) {
        let registration = StandInRegistration(.requiresApproval)
        let result = runSetup(registration, answers: [userOpensSystemSettings])
        #expect(result.outcome == .waitingForApproval && result.questions == [.approvalNeeded] && result.connections == 0)
        #expect(registration.calls == (userOpensSystemSettings ? ["openSystemSettings"] : []))
    }

    @Test func aRegistrationThatNeedsApprovalTellsTheUserOnce() {
        let registration = StandInRegistration(.notRegistered, afterRegistration: .requiresApproval)
        let result = runSetup(registration)
        #expect(result.outcome == .waitingForApproval && result.questions == [.approvalNeeded] && result.connections == 0)
        #expect(registration.calls == ["register"])
    }

    @Test func aWakeForAnAgentThatLaunchdDoesNotKnowTellsTheUser() {
        let registration = StandInRegistration(.enabled)
        let result = runSetup(registration, failures: [.notRegistered])
        #expect(result.outcome == .failed && result.questions == [.failed(detail: "launchd could not find the OpenRun session process.")])
        #expect(registration.calls.isEmpty)
    }

    @Test func aWakeTimeoutDoesNotSuggestOrPerformARegistration() {
        let timeout = SessionWakeFailure.timedOut(limit: .seconds(15))
        let registration = StandInRegistration(.enabled)
        let result = runSetup(registration, failures: [timeout], answers: [true])
        let question = LaunchAgentQuestion.failed(detail: "The OpenRun session process did not answer within 15 seconds.")
        #expect(result.outcome == .failed && result.questions == [question] && result.connections == 1)
        #expect(question.words.title == "OpenRun could not set up the session process")
        #expect(question.words.buttons == ["OK"] && !question.words.message.contains("register"))
        #expect(registration.calls.isEmpty)
    }

    @Test func aHelloThatTakesTooLongIsShownWithItsLimit() {
        let questions = Mutex<[LaunchAgentQuestion]>([])
        let setup = LaunchAgentSetup(
            source: StandInRegistration(.enabled), connect: { throw LaunchAgentSetup.HelloTimedOut(limit: .seconds(15)) },
            ask: { question in questions.withLock { $0.append(question) }; return false })
        #expect(setup.run() == .failed)
        #expect(questions.withLock { $0 } == [.failed(detail: "The OpenRun session process did not answer hello within 15 seconds.")])
    }

    @Test func aNewRegistrationAsksThenUnregistersRegistersAndConnects() {
        let registration = StandInRegistration(.enabled)
        let result = runSetup(registration, answers: [true], registersAgain: true)
        #expect(result.outcome == .ready && result.questions == [.registerAgain])
        #expect(registration.events == ["unregister", "register", "connect"])
        #expect(LaunchAgentQuestion.registerAgain.words == (
            "Register the session process again?",
            "A new registration can end the sessions that run now. Use this after a rebuild, when the session process does not start.",
            ["Register", "Cancel"]))
    }

    @Test func cancelingANewRegistrationChangesNothing() {
        let registration = StandInRegistration(.enabled)
        let result = runSetup(registration, answers: [false], registersAgain: true)
        #expect(result.outcome == .canceled && result.questions == [.registerAgain] && result.connections == 0)
        #expect(registration.calls.isEmpty && registration.status == .enabled)
    }

    @Test func aLaterAttemptCanRecoverFromAConnectionFailure() {
        let registration = StandInRegistration(.enabled)
        let first = runSetup(registration, failures: [.noAnswer(detail: "Not available")])
        let retry = runSetup(registration)
        #expect(first.outcome == .failed && first.questions.count == 1 && first.connections == 1)
        #expect(retry.outcome == .ready && retry.questions.isEmpty && retry.connections == 1)
        #expect(registration.calls.isEmpty)
    }
}
