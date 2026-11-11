import Foundation
import SessionProtocol

/// The question before the close of a session that still runs a program
/// (decision of 2026-11-10). A close ends the work of a row, so a key
/// press alone must not end a program other than a shell at its prompt.
struct CloseQuestion: Equatable {
    /// The shells that wait for a command when they are in the foreground.
    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "xonsh", "pwsh"]

    /// The name of the program that the close would end.
    let program: String

    /// `nil` when the close needs no question: a shell waits at its
    /// prompt, or the app does not know the program and sees no work.
    init?(session: SessionSummary) {
        let foreground = session.foregroundProgram.map { $0.hasPrefix("-") ? String($0.dropFirst()) : $0 } ?? ""
        let isShell = Self.shells.contains(foreground)
        guard session.isInProgress == true || (!foreground.isEmpty && !isShell) else { return nil }
        // A shell in progress runs a command whose name the app does not know.
        program = foreground.isEmpty || isShell ? "A command" : foreground
    }

    var title: String { "Close this session?" }

    var message: String {
        "\(program) still runs in it. A close ends the program and every other process of the session."
    }

    /// The first button is the default one, and it does not end the session.
    var buttons: [String] { ["Cancel", "Close Session"] }
}
