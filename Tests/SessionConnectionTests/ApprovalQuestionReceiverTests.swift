import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import SessionConnection

@Suite struct ApprovalQuestionReceiverTests {
    private static let summary = SessionSummary(identifier: UUID(), folder: "/", command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 0))

    /// The app asks for the questions, receives one, answers it, and sees
    /// its end and then the close.
    @Test func theAppReceivesAQuestionAndAnswersIt() async throws {
        let (appSide, sessionSide) = try MessageConnection.makePair()
        defer { appSide.shutdown(); sessionSide.shutdown() }
        let question = ApprovalQuestion(identifier: UUID(), askingSession: Self.summary, targetSession: Self.summary, request: .attach)
        let answers = Mutex<[ClientMessage]>([])
        Thread {
            defer { sessionSide.shutdown() }
            do {
                guard try sessionSide.receive(ClientMessage.self) == .receiveApprovalQuestions else { return }
                try sessionSide.send(ServerMessage.acknowledged)
                try sessionSide.send(ServerMessage.approvalQuestion(question))
                guard let answer = try sessionSide.receive(ClientMessage.self) else { return }
                answers.withLock { $0.append(answer) }
                try sessionSide.send(ServerMessage.approvalQuestionEnded(identifier: question.identifier))
            } catch {}
        }.start()

        let receiver = try ApprovalQuestionReceiver.open(on: appSide)
        let events = Mutex<[ApprovalQuestionReceiver.Event]>([])
        receiver.startReceiving { event in
            events.withLock { $0.append(event) }
            if case .question(let asked) = event { try? receiver.answer(asked.identifier, allows: false) }
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while events.withLock({ $0.count }) < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(events.withLock { $0 } == [.question(question), .ended(question.identifier), .closed])
        #expect(answers.withLock { $0 } == [.answerApprovalQuestion(identifier: question.identifier, allows: false)])
    }

    @Test func aRefusalEndsTheRequest() throws {
        let (appSide, sessionSide) = try MessageConnection.makePair()
        defer { appSide.shutdown(); sessionSide.shutdown() }
        let failure = SessionFailure(reason: .invalidRequest, message: "Only OpenRun.app receives approval questions.")
        Thread {
            _ = try? sessionSide.receive(ClientMessage.self)
            try? sessionSide.send(ServerMessage.failure(failure))
        }.start()
        #expect(throws: SessionConnectionError.requestFailed(failure)) { try ApprovalQuestionReceiver.open(on: appSide) }
    }
}
