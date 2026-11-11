import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

/// The arguments that make the test process the only program that may
/// answer, as OpenRun.app is for a signed session process.
func testProcessAnswersArguments() throws -> [String] {
    ["--answerer-requirement", "cdhash H\"\(try codeHashOfThisProcess())\""]
}

/// Connects as the app does and asks for the questions. Returns the
/// connection and the answer to the request.
func connectAsAnswerer(to process: RunningSessionProcess) throws -> (MessageConnection, ServerMessage?) {
    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
    _ = try connection.greetSessionProcess(within: .seconds(5))
    try connection.send(ClientMessage.receiveApprovalQuestions)
    return (connection, try connection.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(5))))
}

extension SessionProcessIntegration {
    @Suite struct ApprovalAnswererTests {
        @Test func theProgramThatMeetsTheRequirementReceivesTheQuestions() async throws {
            try await RunningSessionProcess.run(arguments: try testProcessAnswersArguments()) { process in
                let (connection, answer) = try connectAsAnswerer(to: process)
                defer { connection.shutdown() }
                #expect(answer == .acknowledged)
            }
        }

        /// The default requirement names OpenRun.app of the team of the
        /// session process. A test build has no team, so no program meets it.
        @Test func anotherProgramReceivesNoQuestions() async throws {
            try await RunningSessionProcess.run { process in
                let (connection, answer) = try connectAsAnswerer(to: process)
                defer { connection.shutdown() }
                guard case .failure(let failure) = answer else {
                    Issue.record("The session process answered \(String(describing: answer))")
                    return
                }
                #expect(failure.message.contains("Only OpenRun.app"))
            }
        }
    }
}
