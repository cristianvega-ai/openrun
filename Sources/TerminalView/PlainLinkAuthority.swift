/// The rule for the part of a plain address before the path, its authority
/// (decision of 2026-11-10). A letter that looks like an ASCII letter, a hidden
/// character or a full-width full stop in a host can open another site than the
/// one that the text seems to name, so that part must be plain ASCII.
enum PlainLinkAuthority {
    /// The host that an address names, without brackets, or nil when the authority
    /// holds a character that the rule does not permit. `endsAddress` tells whether
    /// the authority runs to the end of the address, with no path, query or fragment.
    static func read(_ address: [Character]) -> (host: String, endsAddress: Bool)? {
        guard let separator = address.indices.first(where: { address[$0...].starts(with: "://") }) else { return nil }
        let rest = address[(separator + 3)...]
        let authority = rest.prefix { !"/?#".contains($0) }
        let userEnd = authority.lastIndex(of: "@")
        let user = userEnd.map { authority[..<$0] } ?? [], name = authority[(userEnd.map { $0 + 1 } ?? authority.startIndex)...]
        guard user.allSatisfy({ isPlain($0) || "-._~%!$&'()*+,;=:".contains($0) }),
            !name.isEmpty, name.allSatisfy({ isPlain($0) || "-.:[]".contains($0) }) else { return nil }
        let host = name.first == "[" ? name.dropFirst().prefix { $0 != "]" } : name.prefix { $0 != ":" }
        return (String(host), authority.count == rest.count)
    }

    /// Whether the text after an address that ends with its authority ends the
    /// host, so `https://good.com.` links but `https://good。com` does not.
    static func endsHost(next: Character?, afterNext: Character?) -> Bool {
        guard let next, !isSpace(next) else { return true }
        if let category = next.unicodeScalars.first?.properties.generalCategory, [.closePunctuation, .finalPunctuation].contains(category) || ")]}>\"'".contains(next) {
            return true
        }
        let isPunctuation = ".,;:!?*".contains(next) || (!next.isASCII && next.unicodeScalars.first?.properties.generalCategory == .otherPunctuation)
        return isPunctuation && (afterNext.map(isSpace) ?? true)
    }

    private static func isPlain(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    private static func isSpace(_ character: Character) -> Bool {
        character.isWhitespace
    }
}
