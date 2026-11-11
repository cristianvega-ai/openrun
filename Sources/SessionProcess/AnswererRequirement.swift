import Foundation
import Security

/// The code requirement that a program must meet to receive and answer
/// approval questions (`specifications/ApprovalQuestion.tla`).
///
/// Any program of the user can connect to the socket. A check of the code
/// signature keeps an agent from answering its own question.
struct AnswererRequirement: Sendable {
    /// The requirement in the code requirement language, or nil when no
    /// program can meet it.
    let text: String?

    /// The bundle identifier of OpenRun.app.
    static let applicationIdentifier = "ai.cristianvega.openrun"

    /// OpenRun.app, signed by the team that signed this process. A build
    /// with no team, such as an ad hoc one, accepts no program. Then each
    /// request on another session is refused.
    static func ofThisProcess() -> AnswererRequirement {
        guard let team = teamIdentifierOfThisProcess() else { return AnswererRequirement(text: nil) }
        return AnswererRequirement(text: "identifier \"\(applicationIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
    }

    /// Whether the running program with this audit token meets the
    /// requirement. The token names one process, also after its number goes
    /// to another one.
    func isMet(byProgramWithAuditToken auditToken: Data) -> Bool {
        guard let text else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func teamIdentifierOfThisProcess() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
