import Foundation
import Security
import SessionProtocol
import Testing
@testable import SessionProcess

/// The code hash of the test process, which names it in a requirement.
/// The test runner is signed ad hoc, so it has no team.
func codeHashOfThisProcess() throws -> String {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    try #require(SecCodeCopySelf([], &code) == errSecSuccess)
    try #require(SecCodeCopyStaticCode(try #require(code), [], &staticCode) == errSecSuccess)
    try #require(SecCodeCopySigningInformation(try #require(staticCode), SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess)
    let hash = try #require((information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data)
    return hash.map { String(format: "%02x", $0) }.joined()
}

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
