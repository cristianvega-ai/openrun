import PseudoTerminal
import TerminalEmulation

/// Tells which line editor reads a command line, from the foreground program.
///
/// zsh and bash edit a line only when they read commands from their terminal.
/// With a command string (`-c`) or a script, they have no line editor, also
/// when the script turns on bracketed paste itself, and also with `-i`: the
/// shell is then interactive, but it runs the script and reads no command
/// line. So a shell has its editor only with no `-c` and no operand after its
/// options.
enum InteractiveShell {
    /// Long options of bash and zsh whose value is the next argument.
    private static let longOptionsWithValue: Set<String> = ["--rcfile", "--init-file", "--emulate"]

    static func lineEditor(of program: ForegroundProgram) -> LineEditor? {
        let editor: LineEditor
        switch program.name {
        case "zsh": editor = .zsh
        case "bash": editor = .readline
        default: return nil
        }
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
            // `-o` and bash's `-O` take the name of an option.
            if letters.contains("o") || letters.contains("O") { remaining = remaining.dropFirst() }
        }
        // An operand is a script.
        return remaining.isEmpty ? editor : nil
    }
}
