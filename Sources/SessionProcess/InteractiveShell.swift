import PseudoTerminal
import TerminalEmulation

/// Tells whether bash reads a command line with readline, from the
/// foreground program. zsh and shells with prompt marks say in their output
/// where their prompt starts (see `ShellPromptTracker`). bash says nothing.
///
/// bash edits a line only when it reads commands from its terminal. With a
/// command string (`-c`) or a script, it has no line editor, also when the
/// script turns on bracketed paste itself, and also with `-i`: the shell is
/// then interactive, but it runs the script and reads no command line. So
/// bash has its editor only with no `-c` and no operand after its options.
enum InteractiveShell {
    /// The names of the shells that the sessions list knows. A shell at its
    /// prompt is not in progress (decision of 2026-11-10).
    private static let shellNames: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "mksh", "oksh", "yash", "tcsh", "csh", "nu", "elvish", "xonsh", "pwsh"]

    static func isShell(_ program: ForegroundProgram) -> Bool {
        shellNames.contains(program.name)
    }

    /// Long options of bash whose value is the next argument.
    private static let longOptionsWithValue: Set<String> = ["--rcfile", "--init-file"]

    static func lineEditor(of program: ForegroundProgram) -> LineEditor? {
        guard program.name == "bash" else { return nil }
        var remaining = program.arguments.dropFirst()
        while let argument = remaining.first {
            if argument == "--" || argument == "-" {
                remaining = remaining.dropFirst()
                break
            }
            guard argument.count > 1, argument.hasPrefix("-") || argument.hasPrefix("+") else { break }
            remaining = remaining.dropFirst()
            if argument.hasPrefix("--") {
                if longOptionsWithValue.contains(argument) { remaining = remaining.dropFirst() }
                continue
            }
            let letters = argument.dropFirst()
            if letters.contains("c") { return nil }
            // `-o` and `-O` take the name of an option.
            if letters.contains("o") || letters.contains("O") { remaining = remaining.dropFirst() }
        }
        // An operand is a script.
        return remaining.isEmpty ? .readline : nil
    }
}
