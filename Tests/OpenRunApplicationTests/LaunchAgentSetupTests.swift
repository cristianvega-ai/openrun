@testable import OpenRunApplication
import SessionLaunch
import Synchronization
import Testing

/// A stand-in for SMAppService, because a test cannot register an agent.
private final class StandInRegistration: LaunchAgentStatusSource {
    private let state: Mutex<(status: LaunchAgentStatus, afterRegistration: LaunchAgentStatus, calls: [String])>

    init(_ status: LaunchAgentStatus, afterRegistration: LaunchAgentStatus = .enabled) {
        state = Mutex((status, afterRegistration, []))
    }

    var calls: [String] { state.withLock { $0.calls } }
    var status: LaunchAgentStatus { state.withLock { $0.status } }
    func register() throws { state.withLock { $0.calls.append("register"); $0.status = $0.afterRegistration } }
    func unregister() throws { state.withLock { $0.calls.append("unregister"); $0.status = .notRegistered } }
    func openSystemSettings() { state.withLock { $0.calls.append("openSystemSettings") } }
}

/// Runs the setup. The connections fail with the failures in order, and
/// the user gives the answers in order. Returns what the setup asked and
/// how often it connected.
private func runSetup(_ registration: StandInRegistration, failures: [SessionWakeFailure?] = [nil], answers: [Bool] = [])
    -> (outcome: LaunchAgentSetup.Outcome, questions: [LaunchAgentQuestion], connections: Int) {
    let record = Mutex((questions: [LaunchAgentQuestion](), connections: 0))
    let setup = LaunchAgentSetup(
        source: registration,
        connect: { () throws(SessionWakeFailure) in
            let index = record.withLock { $0.connections += 1; return $0.connections - 1 }
            if let failure = failures[min(index, failures.count - 1)] { throw failure }
        },
        ask: { question in
            record.withLock { $0.questions.append(question); return answers.count >= $0.questions.count && answers[$0.questions.count - 1] }
        }
    )
    let outcome = setup.run()
    return record.withLock { (outcome, $0.questions, $0.connections) }
}

@Suite struct LaunchAgentSetupTests {
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
        #expect(result.outcome == .failed && result.questions == [.failed(detail: SessionWakeFailure.notRegistered.description)])
        #expect(registration.calls.isEmpty)
    }

    /// Owner decision D3 of 2026-10-27: the user decides, because a new
    /// registration ends the sessions of the old build.
    @Test func aWakeThatTimesOutWhileEnabledRegistersAgainOnlyWhenTheUserAgrees() {
        let timeout = SessionWakeFailure.timedOut(limit: .seconds(15))
        let declined = StandInRegistration(.enabled)
        let refusal = runSetup(declined, failures: [timeout], answers: [false])
        #expect(refusal.outcome == .declined && refusal.questions == [.registerAgain] && refusal.connections == 1)
        #expect(declined.calls.isEmpty)

        let agreed = StandInRegistration(.enabled)
        let renewal = runSetup(agreed, failures: [timeout, nil], answers: [true])
        #expect(renewal.outcome == .ready && renewal.questions == [.registerAgain] && renewal.connections == 2)
        #expect(agreed.calls == ["unregister", "register"])
    }

    @Test func aSecondTimeoutAfterTheNewRegistrationStopsTheSetup() {
        let timeout = SessionWakeFailure.timedOut(limit: .seconds(15))
        let registration = StandInRegistration(.enabled)
        let result = runSetup(registration, failures: [timeout, timeout], answers: [true])
        #expect(result.outcome == .failed && result.connections == 2)
        #expect(result.questions == [.registerAgain, .failed(detail: timeout.description)])
        #expect(registration.calls == ["unregister", "register"])
    }
}
