/// The text that a drop of files from Finder types: the path of each file,
/// quoted for a shell, with a space after each one so the user can type on.
enum DroppedFiles {
    static func text(for paths: [String]) -> String {
        paths.map { quoted($0) + " " }.joined()
    }

    /// A path with only plain characters stays as it is, as Terminal types it. Any
    /// other path goes in single quotes, inside which a shell gives no character a
    /// meaning, so a space, a `$` or a backtick in a name cannot run anything.
    static func quoted(_ path: String) -> String {
        let isPlain = !path.isEmpty && path.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "/._-+,:@%=".unicodeScalars.contains(scalar))
        }
        if isPlain { return path }
        // A quote ends the quoted text, so it goes outside it as an escaped quote.
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
