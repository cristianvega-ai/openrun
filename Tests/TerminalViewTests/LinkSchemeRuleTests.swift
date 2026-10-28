import Foundation
import Testing
@testable import TerminalView

@Suite struct LinkSchemeRuleTests {
    @Test(arguments: ["http://example.com/a", "HTTPS://example.com", "mailto:person@example.com"])
    func webAndMailLinksOpenWithoutAQuestion(_ address: String) throws {
        let target = try #require(LinkSchemeRule.target(for: address))
        #expect(!LinkSchemeRule.needsQuestion(for: target))
    }

    @Test(arguments: ["file:///tmp/a", "openrun://session/123", "ssh://example.com"])
    func otherSchemesAskBeforeTheyOpen(_ address: String) throws {
        let target = try #require(LinkSchemeRule.target(for: address))
        #expect(LinkSchemeRule.needsQuestion(for: target))
    }

    @Test(arguments: ["not a link", "relative/path", "https://", "https://example.com/%GG"])
    func invalidLinksAreRejected(_ address: String) {
        #expect(LinkSchemeRule.target(for: address) == nil)
    }
}
