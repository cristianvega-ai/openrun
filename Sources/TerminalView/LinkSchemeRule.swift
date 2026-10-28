import Foundation

/// The schemes that can open at once, and the schemes that ask first.
enum LinkSchemeRule {
    static func target(for address: String) -> URL? {
        guard let target = URL(string: address, encodingInvalidCharacters: false), let scheme = target.scheme, !scheme.isEmpty else { return nil }
        if ["http", "https"].contains(scheme.lowercased()), (target.host?.isEmpty ?? true) { return nil }
        return target
    }

    static func needsQuestion(for target: URL) -> Bool {
        !["http", "https", "mailto"].contains(target.scheme?.lowercased() ?? "")
    }
}
