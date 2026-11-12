import Darwin
import Foundation

/// A stand-in for `claude -p`, so that no test runs the real agent and
/// spends the owner's subscription. It takes user message lines on
/// standard input and answers each with a recorded turn.
///
/// The environment chooses what it plays:
/// - `FAKE_AGENT_TURNS`: the fixture files, separated by colons. Each user
///   message plays the next file, and the last file repeats.
/// - `FAKE_AGENT_MODE`: one of the cases of `Mode`. The default is `replay`.
/// - `FAKE_AGENT_PAUSE`: the milliseconds between two lines of output.
/// - `FAKE_AGENT_FLOOD_BYTES`: the size of the flood. The default is 8 MiB.
/// - `FAKE_AGENT_PERMISSION_REQUEST`: the file that the hook of the mode
///   `askPermission` gets on its standard input.
struct FakeAgent {
    enum Mode: String {
        /// Each user message plays a recorded turn.
        case replay
        /// What Claude Code does on `--resume` of a conversation that does
        /// not exist: an error result, a message on standard error, and the
        /// exit status 1.
        case unknownConversation
        /// The turn stops before its result until SIGINT comes. Then the
        /// result comes, and the program ends, as Claude Code does.
        case neverEnds
        /// The output stops in the middle of the result line, and the
        /// program fails.
        case cutLine
        /// The program kills itself in the middle of the turn.
        case crash
        /// Many megabytes of text deltas come after the first one.
        case flood
        /// Before the end of the turn, the permission hook of the settings
        /// runs, as Claude Code runs it for a call that needs the user. A
        /// line of the kind `fake_hook` then tells the decision.
        case askPermission
    }

    static let floodLineBytes = 64 * 1024

    let environment: [String: String]

    /// The fake agent in a terminal session, as Claude Code runs for Open
    /// in Terminal. It writes a line, adds the lines of the file in
    /// `FAKE_AGENT_TERMINAL_TURN` to the history of the conversation, and
    /// waits for the end of its input.
    func runInTerminal(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(where: { $0 == "--resume" || $0 == "--session-id" }), flag + 1 < arguments.count else {
            return fail("a run in a terminal needs a conversation", status: 64)
        }
        let conversation = arguments[flag + 1]
        print("The fake agent runs in a terminal with the conversation \(conversation).")
        fflush(stdout)
        if let turn = environment["FAKE_AGENT_TERMINAL_TURN"], let settings = environment["CLAUDE_CONFIG_DIR"], let lines = FileManager.default.contents(atPath: turn) {
            let folder = settings + "/projects/fake-agent", file = folder + "/" + conversation + ".jsonl"
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file) { FileManager.default.createFile(atPath: file, contents: nil) }
            if let handle = FileHandle(forWritingAtPath: file) {
                handle.seekToEndOfFile()
                handle.write(lines)
                try? handle.close()
            }
        }
        while readLine() != nil {}
        return 0
    }

    func run(arguments: [String]) -> Int32 {
        // Claude Code without `-p` is the program for a terminal.
        if !arguments.contains("-p") { return runInTerminal(arguments: arguments) }
        guard let parsed = FakeAgentArguments(arguments) else {
            return fail("the arguments are not the ones that OpenRun gives", status: 64)
        }
        // Claude Code treats a process with this variable as a run inside
        // another run.
        guard environment["CLAUDECODE"] == nil else { return fail("the environment marks a nested run", status: 64) }
        guard let mode = Mode(rawValue: environment["FAKE_AGENT_MODE"] ?? "replay") else { return fail("unknown mode") }
        let identifier = parsed.conversationIdentifier
        if mode == .unknownConversation, parsed.isResume {
            write(#"{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":0,"session_id":"\#(identifier)"}"#)
            return fail("No conversation found with session ID: \(identifier)")
        }
        if mode == .neverEnds { blockInterrupt() }
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
            if let status = play(turn, mode: mode, conversationIdentifier: identifier, hook: parsed.hook) { return status }
        }
        return 0
    }

    /// Writes the turn with the special case of `mode`. Returns the exit
    /// status when the program must end after the turn.
    func play(_ turn: FakeAgentTurn, mode: Mode, conversationIdentifier: String, hook: [String] = []) -> Int32? {
        let end = turn.resultIndex
        var flooded = false
        for (index, line) in turn.lines.enumerated() {
            if index == end, mode == .neverEnds {
                waitForInterrupt()
                turn.lines[end...].forEach { write($0) }
                return 0
            }
            if index == end, mode == .cutLine {
                write(String(decoding: line.utf8.prefix(line.utf8.count / 2), as: UTF8.self), lineEnd: false)
                return 1
            }
            if index == end / 2, mode == .crash { kill(getpid(), SIGKILL) }
            if index == end, mode == .askPermission {
                write(#"{"type":"fake_hook","decision":"\#(FakeAgentHook.decision(of: hook, conversationIdentifier: conversationIdentifier, environment: environment))"}"#)
            }
            write(line)
            if mode == .flood, !flooded, line.contains(#""text_delta""#) {
                flood(conversationIdentifier: conversationIdentifier)
                flooded = true
            }
        }
        return nil
    }

    func flood(conversationIdentifier: String) {
        let byteCount = environment["FAKE_AGENT_FLOOD_BYTES"].flatMap { Int($0) } ?? 8 * 1024 * 1024
        let text = String(repeating: "a", count: Self.floodLineBytes)
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}},"session_id":"\#(conversationIdentifier)","parent_tool_use_id":null}"#
        for _ in 0..<(byteCount / Self.floodLineBytes) { write(line) }
    }

    /// SIGINT stays blocked, so that `sigwait` takes it in place of its
    /// default action, which would end the program.
    func blockInterrupt() {
        var signals = sigset_t()
        sigemptyset(&signals)
        sigaddset(&signals, SIGINT)
        pthread_sigmask(SIG_BLOCK, &signals, nil)
    }

    func waitForInterrupt() {
        var signals = sigset_t()
        sigemptyset(&signals)
        sigaddset(&signals, SIGINT)
        var received: Int32 = 0
        sigwait(&signals, &received)
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
