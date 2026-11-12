import Foundation

/// The address of a web page, from what the user typed or from a link.
public enum BrowserAddress {
    /// The page of a web page that has no address yet.
    public static let blank = "about:blank"

    /// The address as a URL, or `nil` when the browser does not open it.
    /// The browser opens only `http` and `https` pages. Text with no
    /// scheme gets `https`, or `http` for a server on this Mac, such as
    /// `localhost:3000`.
    public static func url(from text: String) -> URL? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains(where: \.isWhitespace) else { return nil }
        if typed == blank { return URL(string: blank) }
        if let scheme = scheme(of: typed) {
            return ["http", "https"].contains(scheme) ? URL(string: typed).flatMap { $0.host == nil ? nil : $0 } : nil
        }
        let host = typed.prefix { $0 != "/" && $0 != ":" }.lowercased()
        let isLocal = host == "localhost" || host == "127.0.0.1" || typed.hasPrefix("[::1]")
        return URL(string: (isLocal ? "http://" : "https://") + typed).flatMap { $0.host == nil ? nil : $0 }
    }

    /// The scheme of text that has one, such as `https` or `file`. A
    /// host with a port, such as `localhost:3000`, has none.
    static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let word = text[..<colon], rest = text[text.index(after: colon)...]
        guard let first = word.first, first.isLetter, word.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else { return nil }
        // After a host, a port follows the colon: digits to the end or to a slash.
        let port = rest.prefix { $0 != "/" }
        if !port.isEmpty, port.allSatisfy(\.isNumber) { return nil }
        return word.lowercased()
    }

    /// Whether a page may go to the address by itself, such as by a link.
    public static func allowsNavigation(to url: URL) -> Bool {
        ["http", "https", "about", "blob", "data"].contains(url.scheme?.lowercased() ?? "")
    }
}
