import Foundation
import SessionProtocol

/// What the app shows for an approval question. The first button denies,
/// so Return never allows by mistake.
struct ApprovalQuestionWords: Equatable {
    var title: String
    var message: String
    var buttons: [String]

    init(_ question: ApprovalQuestion) {
        let asking = Self.name(of: question.askingSession)
        let target = Self.name(of: question.targetSession)
        let reason = "OpenRun asks because one agent must not drive another without you."
        buttons = ["Don't Allow", "Allow"]
        switch question.request {
        case .type(let start, let characterCount):
            title = "Allow a program to type into another session?"
            let shown = start.unicodeScalars.count
            let more = characterCount > shown ? "\n\nThis shows the first \(shown) of \(characterCount) characters." : ""
            message = "A program in \(asking) wants to type into \(target):\n\n\(Self.visible(start))\(more)\n\n\(reason)"
        case .read:
            title = "Allow a program to read another session?"
            message = "A program in \(asking) wants to read the screen and scrollback of \(target).\n\n\(reason)"
        case .attach:
            title = "Allow a program to attach to another session?"
            message = "A program in \(asking) wants to attach to \(target). It could then type into it and read it.\n\n\(reason)"
        case .kill:
            title = "Allow a program to end another session?"
            message = "A program in \(asking) wants to end \(target) and every program in it.\n\n\(reason)"
        }
    }

    /// The folder and the program, then the start of the identifier.
    static func name(of session: SessionSummary) -> String {
        let folder = (session.folder as NSString).lastPathComponent
        let program = session.command.first.map { ($0 as NSString).lastPathComponent } ?? "a program"
        return "the session \(program) in “\(folder)” (\(session.identifierText.prefix(8)))"
    }

    /// Typed text with each control character shown, such as the Return
    /// that would confirm a prompt. A format character, such as a direction
    /// override or a zero-width space, shows as its code, because it can hide
    /// or reorder what the user reads.
    static func visible(_ text: String) -> String {
        var shown = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0D: shown += "⏎"
            case 0x0A: shown += "␤"
            case 0x09: shown += "⇥"
            case 0x1B: shown += "⎋"
            case 0x00..<0x20: shown += "^" + String(UnicodeScalar(UInt8(scalar.value + 0x40)))
            case 0x7F: shown += "⌫"
            case 0x80...0x9F: shown += Self.code(of: scalar)
            default:
                switch scalar.properties.generalCategory {
                case .format, .lineSeparator, .paragraphSeparator: shown += Self.code(of: scalar)
                default: shown.unicodeScalars.append(scalar)
                }
            }
        }
        return shown
    }

    private static func code(of scalar: Unicode.Scalar) -> String {
        "⟨U+" + String(format: "%04X", scalar.value) + "⟩"
    }
}
