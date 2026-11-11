import Foundation
import Security
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionProcess

@Suite struct AnswererRequirementTests {
    private func auditTokenOfThisProcess() throws -> Data {
        let (first, second) = try MessageConnection.makePair()
        defer { first.shutdown(); second.shutdown() }
        return try first.peerProcess().auditToken
    }

    @Test func aProgramThatMeetsTheRequirementMayAnswer() throws {
        let requirement = AnswererRequirement(text: "cdhash H\"\(try codeHashOfThisProcess())\"")
        #expect(requirement.isMet(byProgramWithAuditToken: try auditTokenOfThisProcess()))
    }

    @Test func anotherProgramMayNotAnswer() throws {
        let token = try auditTokenOfThisProcess()
        #expect(!AnswererRequirement(text: "identifier \"\(AnswererRequirement.applicationIdentifier)\"").isMet(byProgramWithAuditToken: token))
        #expect(!AnswererRequirement(text: nil).isMet(byProgramWithAuditToken: token))
        #expect(!AnswererRequirement(text: "not a requirement").isMet(byProgramWithAuditToken: token))
    }

    /// A token of no process names no code, so it meets no requirement.
    @Test func aTokenOfNoProcessMayNotAnswer() throws {
        let requirement = AnswererRequirement(text: "cdhash H\"\(try codeHashOfThisProcess())\"")
        #expect(!requirement.isMet(byProgramWithAuditToken: Data(count: 32)))
    }
}
