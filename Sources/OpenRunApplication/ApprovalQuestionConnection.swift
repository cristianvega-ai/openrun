import AppKit
import OSLog
import SessionConnection
import SessionLaunch
import SessionProtocol

/// Keeps the connection on which the app receives approval questions. After
/// the session process ends, it connects again, and a wake starts the next
/// one. So the session process runs while the app runs.
@MainActor
final class ApprovalQuestionConnection {
    private let socket: SocketLocation
    private var alerts: ApprovalQuestionAlerts?
    private var receiver: ApprovalQuestionReceiver?
    private var isStarted = false
    private var retryDelay = Duration.seconds(1)
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "ApprovalQuestionConnection")

    init(socket: SocketLocation, runModal: @escaping ApprovalQuestionAlerts.RunModal = ModalAlert.runStandardModal) {
        self.socket = socket
        alerts = ApprovalQuestionAlerts(answer: { [weak self] identifier, allows in
            DispatchQueue.main.async { MainActor.assumeIsolated { try? self?.receiver?.answer(identifier, allows: allows) } }
        }, runModal: runModal)
    }

    /// Whether the session process accepted the connection, for tests.
    var isConnected: Bool { receiver != nil }

    /// Connects once the session process is ready. Later calls do nothing.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        connect()
    }

    private func connect() {
        let socket = socket
        Thread.detachNewThread { [weak self] in
            let result = Result { try SessionClient(location: socket, helloTimeLimit: SessionWake.answerTimeLimit).receiveApprovalQuestions() }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.connected(result) } }
        }
    }

    private func connected(_ result: Result<ApprovalQuestionReceiver, any Error>) {
        switch result {
        case .success(let receiver):
            self.receiver = receiver
            retryDelay = .seconds(1)
            receiver.startReceiving { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(event) } }
            }
        case .failure(SessionConnectionError.requestFailed(let failure)):
            // A build with no team, or an app whose bundle a rebuild replaced
            // while it ran. Each request on another session is refused until
            // a later try works.
            logger.error("The session process refused the approval questions: \(failure.message, privacy: .public)")
            retryDelay = .seconds(30)
            connectLater()
        case .failure(let error):
            logger.error("No connection for approval questions: \(String(describing: error), privacy: .private)")
            connectLater()
        }
    }

    private func received(_ event: ApprovalQuestionReceiver.Event) {
        alerts?.handle(event)
        switch event {
        case .closed, .failed:
            receiver = nil
            connectLater()
        case .question, .ended:
            break
        }
    }

    private func connectLater() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, .seconds(30))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.connect()
        }
    }
}
