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

    /// In an ad hoc build, the answerer is the app bundle that holds the
    /// session process, by the code hash of its main program.
    @Test func anAdHocBundleNamesItsMainProgramByItsCodeHash() throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try AdHocBundle.make(named: "Test", in: folder, mainProgram: RunningSessionProcess.commandExecutable)
        let requirement = AnswererRequirement.ofApplication(atPath: bundle.path)
        #expect(requirement.text == "cdhash H\"\(try AdHocBundle.codeHash(of: bundle))\"")
        #expect(AnswererRequirement.ofApplication(atPath: folder.path).text == nil)
        let program = bundle.path + "/Contents/MacOS/openrun-session"
        #expect(ApplicationBundle.path(holdingExecutableAt: program) == bundle.path)
        #expect(ApplicationBundle.path(holdingExecutableAt: RunningSessionProcess.sessionExecutable.path) == nil)
    }
}
