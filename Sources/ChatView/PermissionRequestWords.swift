import AgentConversation
import Foundation

/// The words of a permission request: what the agent wants to do, and
/// everything that the user must read before an answer.
struct PermissionRequestWords: Equatable {
    /// A piece of what the request shows, from the top.
    enum Part: Equatable {
        /// Text in full in a box of code, such as a command.
        case text(String)
        /// A change of a file.
        case diff(UnifiedDiff)
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
        let reason = input.text("reason")
        let action: String
        switch request.toolName {
        case "Bash", "commandExecution":
            action = "run a command"
            subject = input.text("command") ?? ""
            parts = [.text(subject)]
            if let folder = input.text("cwd") { parts.append(.note("In the folder " + folder)) }
        case "fileChange":
            action = "change files"
            let changes = input.value("changes")?.array ?? []
            subject = changes.compactMap { $0["path"]?.string }.joined(separator: ", ")
            parts = changes.flatMap(Self.parts(ofChange:))
            if let root = input.text("grantRoot") { parts.append(.note("It also asks to write anywhere in " + root)) }
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            subject = input.text("file_path") ?? input.text("notebook_path") ?? ""
            parts = [.note(subject)]
            action = Self.fileParts(of: request.toolName, &input, into: &parts)
        case "WebFetch":
            action = "read a web page"
            subject = input.text("url") ?? ""
            parts = [.text(subject)]
        default:
            action = "use \(request.toolName)"
            subject = request.toolName
        }
        title = "\(agentName) wants to \(action)"
        if let reason { parts.insert(.note("Reason: " + reason), at: 0) }
        let rest = input.rest
        if !rest.isEmpty { parts += parts.isEmpty ? [.text(rest)] : [.note("More input:"), .text(rest)] }
        subject = Self.visible(subject)
        parts = parts.map(Self.visible)
    }

    /// The parts of a change of a file, and the words for the action.
    private static func fileParts(of tool: String, _ input: inout PermissionRequestInput, into parts: inout [Part]) -> String {
        switch tool {
        case "Write":
            parts.append(.text(input.text("content") ?? ""))
            return "write a file"
        case "NotebookEdit":
            parts.append(.text(input.text("new_source") ?? ""))
            return "edit a notebook"
        case "MultiEdit":
            let edits = input.value("edits")?.array ?? []
            var diff = UnifiedDiff(old: "", new: "", title: nil)
            for (index, edit) in edits.enumerated() {
                let every = edit["replace_all"]?.bool == true ? ", every place" : ""
                diff.append(UnifiedDiff(old: edit["old_string"]?.string ?? "", new: edit["new_string"]?.string ?? "",
                                        title: "Edit \(index + 1) of \(edits.count)\(every)"))
            }
            parts.append(.diff(diff))
        default:
            parts.append(.diff(UnifiedDiff(old: input.text("old_string") ?? "", new: input.text("new_string") ?? "", title: nil)))
            if input.value("replace_all")?.bool == true { parts.append(.note("It changes every place where the old text occurs.")) }
        }
        return "edit a file"
    }

    /// The parts of one file of a change of Codex: what happens to the
    /// file, and its diff, or its content when the file is new or goes.
    private static func parts(ofChange change: JSONValue) -> [Part] {
        let path = change["path"]?.string ?? ""
        let kind = change["kind"]?.string ?? change["kind"]?["type"]?.string ?? ""
        let text = change["diff"]?.string ?? ""
        let move = change["kind"]?["move_path"]?.string.map { ", and move it to " + $0 } ?? ""
        let diff = UnifiedDiff(text)
        switch kind {
        case "add": return [.note("New file " + path), .diff(diff.lines.isEmpty ? UnifiedDiff(old: "", new: text, title: nil) : diff)]
        case "delete": return [.note("Delete " + path)] + (text.isEmpty ? [] : [.diff(diff.lines.isEmpty ? UnifiedDiff(old: text, new: "", title: nil) : diff)])
        default: return [.note("Change " + path + move), diff.lines.isEmpty ? .text(text) : .diff(diff)]
        }
    }

    private static func visible(_ part: Part) -> Part {
        switch part {
        case .text(let text): return .text(visible(text))
        case .note(let text): return .note(visible(text))
        case .diff(var diff):
            diff.mapText { Substring(visible(String($0))) }
            return .diff(diff)
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
