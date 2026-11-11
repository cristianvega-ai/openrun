import AgentConversation
import Foundation

/// The words of a permission request: what the agent wants to do, and
/// everything that the user must read before an answer.
struct PermissionRequestWords: Equatable {
    /// A piece of what the request shows, from the top.
    enum Part: Equatable {
        /// Text in full in a box of code, such as a command.
        case text(String)
        /// A quiet line of prose, such as a path or a reason.
        case note(String)
    }

    var title: String
    /// The command, the path or the name of the tool, for the folded line.
    var subject: String
    var parts: [Part] = []

    init(_ item: PermissionRequestItem, agentName: String) {
        let request = item.request
        var input = PermissionRequestInput(request.input)
        let action: String
        switch request.toolName {
        case "Bash":
            action = "run a command"
            subject = input.text("command") ?? ""
            parts = [.text(subject)]
        case "WebFetch":
            action = "read a web page"
            subject = input.text("url") ?? ""
            parts = [.text(subject)]
        default:
            action = "use \(request.toolName)"
            subject = request.toolName
        }
        title = "\(agentName) wants to \(action)"
        let rest = input.rest
        if !rest.isEmpty { parts += parts.isEmpty ? [.text(rest)] : [.note("More input:"), .text(rest)] }
        subject = Self.visible(subject)
        parts = parts.map(Self.visible)
    }

    private static func visible(_ part: Part) -> Part {
        switch part {
        case .text(let text): .text(visible(text))
        case .note(let text): .note(visible(text))
        }
    }

    /// The text with control characters, other than a line end or a tab,
    /// format characters, and characters that draw as blank but are not a
    /// space shown as marks or codes. A direction override, a zero-width
    /// space or a filler can hide or reorder what the user reads.
    static func visible(_ text: String) -> String {
        var shown = ""
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            defer { previous = scalar }
            if isBlank(scalar, after: previous) {
                shown += code(of: scalar)
                continue
            }
            switch scalar.value {
            case 0x0A, 0x09: shown.unicodeScalars.append(scalar)
            case 0x0D: shown += "⏎"
            case 0x1B: shown += "⎋"
            case 0x00..<0x20: shown += "^" + String(UnicodeScalar(UInt8(scalar.value + 0x40)))
            case 0x7F: shown += "⌫"
            case 0x80...0x9F: shown += code(of: scalar)
            default:
                switch scalar.properties.generalCategory {
                case .format, .lineSeparator, .paragraphSeparator: shown += code(of: scalar)
                default: shown.unicodeScalars.append(scalar)
                }
            }
        }
        return shown
    }

    /// Whether a character draws as blank, or as nothing, but is not a
    /// space: a filler, a blank Braille cell, another kind of space, or a
    /// character that a font ignores. A variation selector after an emoji
    /// only chooses its look, so it stays.
    private static func isBlank(_ scalar: Unicode.Scalar, after previous: Unicode.Scalar?) -> Bool {
        let properties = scalar.properties
        if properties.isVariationSelector { return previous?.properties.isEmoji != true }
        if scalar.value == 0x2800 { return true }
        if properties.generalCategory == .spaceSeparator { return scalar.value != 0x20 }
        return properties.isDefaultIgnorableCodePoint
    }

    private static func code(of scalar: Unicode.Scalar) -> String {
        "⟨U+" + String(format: "%04X", scalar.value) + "⟩"
    }
}
