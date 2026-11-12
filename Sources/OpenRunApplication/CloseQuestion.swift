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

    /// `nil` when the close needs no question: a shell reads the keys,
    /// or the app does not know the program.
    ///
    /// The work of the session does not count. A shell that just wrote
    /// its prompt is in progress for two seconds, and a new session must
    /// close at once.
    init?(session: SessionSummary) {
        let foreground = session.foregroundProgram.map { $0.hasPrefix("-") ? String($0.dropFirst()) : $0 } ?? ""
        guard !foreground.isEmpty, !Self.shells.contains(foreground) else { return nil }
        program = foreground
    }

    var title: String { "Close this terminal?" }

    var message: String {
        "\(program) still runs in it. A close ends the program and every other process of the terminal."
    }

    /// The first button is the default one, and it does not end the terminal.
    var buttons: [String] { ["Cancel", "Close Terminal"] }
}
