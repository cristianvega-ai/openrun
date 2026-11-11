import Darwin
import Foundation

/// A stand-in for `claude -p`, so that no test runs the real agent and
/// spends the owner's subscription. It takes user message lines on
/// standard input and answers each with a recorded turn.
///
/// The environment chooses what it plays:
/// - `FAKE_AGENT_TURNS`: the fixture files, separated by colons. Each user
///   message plays the next file, and the last file repeats.
/// - `FAKE_AGENT_PAUSE`: the milliseconds between two lines of output.
struct FakeAgent {
    let environment: [String: String]

    func run(arguments: [String]) -> Int32 {
        guard let parsed = FakeAgentArguments(arguments) else {
            return fail("the arguments are not the ones that OpenRun gives", status: 64)
        }
        // Claude Code treats a process with this variable as a run inside
        // another run.
        guard environment["CLAUDECODE"] == nil else { return fail("the environment marks a nested run", status: 64) }
        let identifier = parsed.conversationIdentifier
        let files = (environment["FAKE_AGENT_TURNS"] ?? "").split(separator: ":").map(String.init)
        var played = 0
        while let line = readLine() {
            guard let message = FakeAgentTurn.object(line), message["type"] as? String == "user", !files.isEmpty else {
                return fail("a line of standard input is not a user message, or no turn was given")
            }
            let file = files[min(played, files.count - 1)]
            played += 1
            guard let turn = try? FakeAgentTurn(file: file, conversationIdentifier: identifier, userMessage: message) else {
                return fail("a turn cannot be read")
            }
            turn.lines.forEach { write($0) }
        }
        return 0
    }

    func write(_ text: String, lineEnd: Bool = true) {
        // A reader that went away ends the program, as it ends Claude Code.
        do { try FileHandle.standardOutput.write(contentsOf: Data((lineEnd ? text + "\n" : text).utf8)) } catch { exit(1) }
        if let pause = environment["FAKE_AGENT_PAUSE"].flatMap({ UInt32($0) }), pause > 0 { usleep(pause * 1000) }
    }

    func fail(_ problem: String, status: Int32 = 1) -> Int32 {
        try? FileHandle.standardError.write(contentsOf: Data("\(problem)\n".utf8))
        return status
    }
}
