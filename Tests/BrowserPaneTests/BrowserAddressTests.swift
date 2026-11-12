import BrowserPane
import Foundation
import Testing

@Suite struct BrowserAddressTests {
    @Test func textWithNoSchemeGetsOneAndOnlyWebPagesOpen() {
        let addresses = [
            "example.com/docs": "https://example.com/docs", " https://example.com ": "https://example.com", "HTTP://example.com": "HTTP://example.com",
            "localhost:3000": "http://localhost:3000", "localhost": "http://localhost", "127.0.0.1:8080/a?b=c": "http://127.0.0.1:8080/a?b=c",
            "[::1]:8080": "http://[::1]:8080", "example.com:8443/x": "https://example.com:8443/x", "about:blank": "about:blank",
        ]
        for (typed, expected) in addresses { #expect(BrowserAddress.url(from: typed)?.absoluteString == expected, "\(typed)") }
        // A file, a script, and text that is no address do not open.
        for refused in ["", "  ", "two words", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,x", "mailto:a@b.c", "https://", "about:config"] {
            #expect(BrowserAddress.url(from: refused) == nil, "\(refused)")
        }
    }

    @Test func aPageGoesOnlyToWebAddressesByItself() throws {
        for allowed in ["https://example.com", "http://localhost:3000", "about:blank", "blob:https://example.com/1", "data:text/html,x"] {
            #expect(BrowserAddress.allowsNavigation(to: try #require(URL(string: allowed))))
        }
        for refused in ["file:///etc/passwd", "mailto:a@b.c", "x-apple.systempreferences:", "javascript:alert(1)"] {
            #expect(!BrowserAddress.allowsNavigation(to: try #require(URL(string: refused))))
        }
    }
}
