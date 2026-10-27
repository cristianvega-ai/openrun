import Dispatch
import Foundation
import Synchronization
import XPC

/// The client side of the start on demand. A message to the Mach service
/// of the launch agent makes launchd start the session process, which
/// answers once its socket listens.
public enum SessionWake {
    /// launchd holds a start for 10 seconds after a run that was shorter
    /// than 10 seconds, so the limit must be longer than that.
    public static let answerTimeLimit: Duration = .seconds(15)

    /// Sends one wake request and returns the socket path of the answer.
    public static func wake(
        machServiceName: String = LaunchAgentNames.machServiceName(in: ProcessInfo.processInfo.environment),
        timeLimit: Duration = answerTimeLimit
    ) throws(SessionWakeFailure) -> String {
        let session: XPCSession
        do {
            // A name that launchd does not know fails here at once.
            session = try XPCSession(machService: machServiceName)
        } catch {
            throw .notRegistered
        }
        defer { session.cancel(reason: "The wake request is done.") }
        let outcome = Mutex<Result<String, SessionWakeFailure>?>(nil)
        let answered = DispatchSemaphore(value: 0)
        do {
            try session.send(WakeRequest()) { (result: Result<XPCReceivedMessage, XPCRichError>) in
                outcome.withLock { $0 = interpret(result) }
                answered.signal()
            }
        } catch {
            throw .noAnswer(detail: "\(error)")
        }
        // A registration that launchd cannot start never answers.
        let (seconds, attoseconds) = timeLimit.components
        let deadline = DispatchTime.now() + .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000))
        guard answered.wait(timeout: deadline) == .success else { throw .timedOut(limit: timeLimit) }
        switch outcome.withLock({ $0 }) {
        case .success(let path): return path
        case .failure(let failure): throw failure
        case nil: throw .noAnswer(detail: "The answer is missing.")
        }
    }

    private static func interpret(_ result: Result<XPCReceivedMessage, XPCRichError>) -> Result<String, SessionWakeFailure> {
        switch result {
        case .success(let message):
            guard let answer = try? message.decode(as: WakeAnswer.self) else { return .failure(.noAnswer(detail: "The answer is not a socket path.")) }
            return .success(answer.socketPath)
        case .failure(let error):
            return .failure(.noAnswer(detail: "\(error)"))
        }
    }
}
