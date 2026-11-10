import PseudoTerminal
@testable import SessionProcess
import TerminalEmulation
import Testing

@Suite struct InteractiveShellTests {
    private static func editor(_ name: String, _ arguments: [String]) -> LineEditor? {
        InteractiveShell.lineEditor(of: ForegroundProgram(name: name, arguments: arguments))
    }

    @Test(arguments: [
        ["-bash"], ["bash"], ["bash", "--login"], ["bash", "--rcfile", "/tmp/environment"], ["bash", "--noprofile", "-O", "extglob"],
    ])
    func bashThatReadsItsTerminalHasReadline(arguments: [String]) {
        #expect(Self.editor("bash", arguments) == .readline)
    }

    @Test(arguments: [
        ["bash", "-c", "printf x"], ["bash", "-ec", "true"], ["bash", "script.sh"], ["bash", "--", "script.sh"],
        // With -i the shell is interactive, but it runs the script and edits no line.
        ["bash", "-i", "script.sh"],
    ])
    func aShellWithACommandOrAScriptHasNoEditor(arguments: [String]) {
        #expect(Self.editor(arguments[0], arguments) == nil)
    }

    /// zsh says in its output where its prompt starts, so its name gives no
    /// editor.
    @Test func anotherProgramHasNoEditor() {
        #expect(Self.editor("zsh", ["-zsh"]) == nil)
        #expect(Self.editor("fish", ["fish"]) == nil)
        #expect(Self.editor("claude", ["claude"]) == nil)
    }
}
