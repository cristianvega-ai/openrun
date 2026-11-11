import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

/// The next message for the app, or nil after ten seconds.
private func next(_ app: MessageConnection) throws -> ServerMessage? {
    try app.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(10)))
}

extension SessionProcessIntegration {
    /// A program in one session asks to type into another one, and the test
    /// answers as the app (ApprovalQuestion.tla).
    @Suite struct ApprovalQuestionFlowTests {
        @Test(arguments: [true, false]) func theAnswerOfTheUserDecides(allows: Bool) async throws {
            try await RunningSessionProcess.run(arguments: try testProcessAnswersArguments()) { process in
                let (app, answer) = try connectAsAnswerer(to: process)
                defer { app.shutdown() }
                #expect(answer == .acknowledged)
                let target = try process.createSession(program: ["/bin/sh"])
                let script = "\(openrun(process, "send --enter \(target) 'echo typed-$((6*7))'")); echo send=$?; exec sleep 60"
                let caller = try process.createSession(program: ["/bin/sh", "-c", script])

                guard case .approvalQuestion(let question) = try next(app) else {
                    Issue.record("The app received no question.")
                    return
                }
                #expect(question.askingSession.identifierText == caller)
                #expect(question.targetSession.identifierText == target)
                #expect(question.request == .typing("echo typed-$((6*7))\r"))
                try app.send(ClientMessage.answerApprovalQuestion(identifier: question.identifier, allows: allows))
                #expect(try next(app) == .approvalQuestionEnded(identifier: question.identifier))
                #expect(await process.waitForScreen(of: caller, containing: allows ? "send=0" : "send=1"))
                if allows {
                    #expect(await process.waitForScreen(of: target, containing: "typed-42"))
                } else {
                    #expect(try !process.screenText(of: target).contains("typed-"))
                }
            }
        }

    }
}
