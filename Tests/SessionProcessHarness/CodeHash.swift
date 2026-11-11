import Foundation
import Security
import Testing

/// The code hash of the test process, which names it in a requirement.
/// The test runner is signed ad hoc, so it has no team.
public func codeHashOfThisProcess() throws -> String {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    try #require(SecCodeCopySelf([], &code) == errSecSuccess)
    try #require(SecCodeCopyStaticCode(try #require(code), [], &staticCode) == errSecSuccess)
    try #require(SecCodeCopySigningInformation(try #require(staticCode), SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess)
    let hash = try #require((information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data)
    return hash.map { String(format: "%02x", $0) }.joined()
}
