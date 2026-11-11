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

        /// Each request asks with its own kind, so the user never allows a
        /// read that then kills.
        @Test(arguments: [("read", ApprovalQuestion.Request.read), ("attach", .attach), ("kill", .kill)])
        func eachRequestAsksWithItsKind(command: String, request: ApprovalQuestion.Request) async throws {
            try await RunningSessionProcess.run(arguments: try testProcessAnswersArguments()) { process in
                let (app, _) = try connectAsAnswerer(to: process)
                defer { app.shutdown() }
                let target = try process.createSession(program: ["/bin/sh"])
                let caller = try process.createSession(program: ["/bin/sh", "-c", "\(openrun(process, "\(command) \(target)")); echo done=$?; exec sleep 60"])
                guard case .approvalQuestion(let question) = try next(app) else {
                    Issue.record("The app received no question.")
                    return
                }
                #expect(question.request == request)
                try app.send(ClientMessage.answerApprovalQuestion(identifier: question.identifier, allows: false))
                #expect(await process.waitForScreen(of: caller, containing: "done=1"))
                #expect(try process.listedIdentifiers().contains(target))
            }
        }

        /// A late answer to the question of a program that left does nothing.
        @Test func aCallerThatLeavesEndsItsQuestion() async throws {
            try await RunningSessionProcess.run(arguments: try testProcessAnswersArguments()) { process in
                let (app, _) = try connectAsAnswerer(to: process)
                defer { app.shutdown() }
                let target = try process.createSession(program: ["/bin/sh"])
                let caller = try process.createSession(program: ["/bin/sh", "-c", openrun(process, "send --enter \(target) 'echo typed-late'")])
                guard case .approvalQuestion(let question) = try next(app) else {
                    Issue.record("The app received no question.")
                    return
                }
                #expect(try process.runCommand(["kill", caller]).status == 0)
                #expect(try next(app) == .approvalQuestionEnded(identifier: question.identifier))
                try app.send(ClientMessage.answerApprovalQuestion(identifier: question.identifier, allows: true))
                #expect(try process.runCommand(["send", "--enter", target, "echo next-$((6*7))"]).status == 0)
                #expect(await process.waitForScreen(of: target, containing: "next-42"))
                #expect(try !process.screenText(of: target).contains("typed-late"))
            }
        }
    }
}
