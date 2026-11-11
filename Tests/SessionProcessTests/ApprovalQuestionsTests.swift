import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
@testable import SessionProcess

/// A connection of the app, which keeps what it received.
private final class Answerer: Sendable {
    private let received = Mutex<[ServerMessage]>([])
    var key: ObjectIdentifier { ObjectIdentifier(self) }
    var send: ApprovalQuestions.Send { { message in self.received.withLock { $0.append(message) } } }
    var messages: [ServerMessage] { received.withLock { $0 } }
}

private func makeQuestion() -> ApprovalQuestion {
    let summary = SessionSummary(identifier: UUID(), folder: "/", command: ["/bin/sh"], size: SessionSize(columns: 80, rows: 24), createdAt: .now)
    return ApprovalQuestion(identifier: UUID(), askingSession: summary, targetSession: summary, request: .read)
}

@Suite struct ApprovalQuestionsTests {
    @Test func withNoAnswererAQuestionEndsAtOnce() async {
        #expect(await ApprovalQuestions().ask(makeQuestion()) == .noAnswerer)
    }

    @Test func theAnswerOfTheAppEndsTheQuestion() async {
        for allows in [true, false] {
            let questions = ApprovalQuestions()
            let app = Answerer()
            await questions.addAnswerer(app.key, send: app.send)
            let question = makeQuestion()
            let outcome = Task { await questions.ask(question) }
            #expect(await eventually { app.messages == [.approvalQuestion(question)] })
            await questions.answer(question.identifier, allows: allows, from: app.key)
            #expect(await outcome.value == (allows ? .allowed : .denied))
            #expect(app.messages.last == .approvalQuestionEnded(identifier: question.identifier))
        }
    }

    /// An answer that names another question, or that comes from a
    /// connection that does not hold the question, changes nothing. A late
    /// answer changes nothing either.
    @Test func onlyTheAnswerToTheQuestionCounts() async {
        let questions = ApprovalQuestions(timeLimit: .milliseconds(300))
        let app = Answerer()
        let stranger = Answerer()
        await questions.addAnswerer(app.key, send: app.send)
        let question = makeQuestion()
        let outcome = Task { await questions.ask(question) }
        #expect(await eventually { !app.messages.isEmpty })
        await questions.answer(UUID(), allows: true, from: app.key)
        await questions.answer(question.identifier, allows: true, from: stranger.key)
        #expect(await outcome.value == .timedOut)
        await questions.answer(question.identifier, allows: true, from: app.key)
        #expect(app.messages == [.approvalQuestion(question), .approvalQuestionEnded(identifier: question.identifier)])
    }

    /// One session cannot pile up alerts. A question of another session
    /// still reaches the app.
    @Test func eachSessionHasOneQuestionAtATime() async {
        let questions = ApprovalQuestions()
        let app = Answerer()
        await questions.addAnswerer(app.key, send: app.send)
        let first = makeQuestion()
        var second = makeQuestion()
        second.askingSession = first.askingSession
        let outcome = Task { await questions.ask(first) }
        #expect(await eventually { !app.messages.isEmpty })
        #expect(await questions.ask(second) == .anotherQuestionWaits)
        let other = makeQuestion()
        let otherOutcome = Task { await questions.ask(other) }
        #expect(await eventually { app.messages.count == 2 })
        await questions.answer(first.identifier, allows: false, from: app.key)
        await questions.answer(other.identifier, allows: false, from: app.key)
        let outcomes = (await outcome.value, await otherOutcome.value)
        #expect(outcomes == (.denied, .denied))
    }

    @Test func aCallerThatLeavesWithdrawsItsQuestion() async {
        let questions = ApprovalQuestions()
        let app = Answerer()
        await questions.addAnswerer(app.key, send: app.send)
        let question = makeQuestion()
        let outcome = Task { await questions.ask(question) }
        #expect(await eventually { !app.messages.isEmpty })
        outcome.cancel()
        #expect(await outcome.value == .withdrawn)
        #expect(app.messages.last == .approvalQuestionEnded(identifier: question.identifier))
    }

    /// A connection that comes later receives the questions that wait. The
    /// question ends when the last connection that holds it leaves.
    @Test func aQuestionLastsWhileAConnectionHoldsIt() async {
        let questions = ApprovalQuestions()
        let first = Answerer()
        let second = Answerer()
        await questions.addAnswerer(first.key, send: first.send)
        let question = makeQuestion()
        let outcome = Task { await questions.ask(question) }
        #expect(await eventually { !first.messages.isEmpty })
        await questions.addAnswerer(second.key, send: second.send)
        #expect(second.messages == [.approvalQuestion(question)])
        await questions.removeAnswerer(first.key)
        #expect(second.messages == [.approvalQuestion(question)], "the second connection still holds it")
        await questions.removeAnswerer(second.key)
        #expect(await outcome.value == .noAnswerer)
    }
}
