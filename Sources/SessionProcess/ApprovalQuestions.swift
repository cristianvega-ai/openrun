import Foundation
import SessionProtocol

/// The approval questions that wait for the user, and the connections of the
/// app that answer them. Each step of `specifications/ApprovalQuestion.tla`
/// is one step of this actor.
///
/// A question ends once: at an answer, at the time limit, when the program
/// that asked leaves, or when no connection holds it any more. A later
/// answer changes nothing.
actor ApprovalQuestions {
    enum Outcome: Equatable, Sendable {
        case allowed
        case denied
        case timedOut
        /// No connection of the app could take the question, or the last
        /// one that held it left.
        case noAnswerer
        /// The program that asked left.
        case withdrawn
    }

    typealias Send = @Sendable (ServerMessage) -> Void

    private struct Answerer {
        let send: Send
        /// The questions that this connection received and that still wait.
        var holds: Set<UUID> = []
    }

    private struct Waiting {
        let question: ApprovalQuestion
        let continuation: CheckedContinuation<Outcome, Never>
        var timer: Task<Void, Never>?
    }

    private var answerers: [ObjectIdentifier: Answerer] = [:]
    private var waiting: [UUID: Waiting] = [:]
    private let timeLimit: Duration

    init(timeLimit: Duration = .seconds(120)) {
        self.timeLimit = timeLimit
    }

    /// Adds a connection that passed the checks. It receives every question
    /// that waits.
    func addAnswerer(_ key: ObjectIdentifier, send: @escaping Send) {
        answerers[key] = Answerer(send: send, holds: Set(waiting.keys))
        for entry in waiting.values { send(.approvalQuestion(entry.question)) }
    }

    func removeAnswerer(_ key: ObjectIdentifier) {
        guard answerers.removeValue(forKey: key) != nil else { return }
        for identifier in waiting.keys where !answerers.values.contains(where: { $0.holds.contains(identifier) }) {
            end(identifier, .noAnswerer)
        }
    }

    /// Asks the user, and returns when the question ends. A cancelled task
    /// withdraws its question.
    func ask(_ question: ApprovalQuestion) async -> Outcome {
        guard !answerers.isEmpty else { return .noAnswerer }
        let identifier = question.identifier
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { return continuation.resume(returning: .withdrawn) }
                waiting[identifier] = Waiting(question: question, continuation: continuation)
                for key in answerers.keys {
                    answerers[key]?.holds.insert(identifier)
                    answerers[key]?.send(.approvalQuestion(question))
                }
                waiting[identifier]?.timer = Task { [timeLimit] in
                    try? await Task.sleep(for: timeLimit)
                    guard !Task.isCancelled else { return }
                    self.end(identifier, .timedOut)
                }
            }
        } onCancel: {
            Task { await self.end(identifier, .withdrawn) }
        }
    }

    /// Takes an answer only from a connection that holds the question.
    func answer(_ identifier: UUID, allows: Bool, from key: ObjectIdentifier) {
        guard answerers[key]?.holds.contains(identifier) == true else { return }
        end(identifier, allows ? .allowed : .denied)
    }

    private func end(_ identifier: UUID, _ outcome: Outcome) {
        guard let entry = waiting.removeValue(forKey: identifier) else { return }
        entry.timer?.cancel()
        for key in answerers.keys where answerers[key]?.holds.remove(identifier) != nil {
            answerers[key]?.send(.approvalQuestionEnded(identifier: identifier))
        }
        entry.continuation.resume(returning: outcome)
    }
}
