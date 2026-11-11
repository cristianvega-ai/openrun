import Foundation
import PseudoTerminal
@testable import SessionProcess
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing

/// A client with its own copy of the screen, as the terminal view has. It
/// takes the output and each new size in the order that they arrive.
private final class FollowingViewer {
    let peer: MessageConnection
    let connection: ClientConnection
    private(set) var screen: Terminal?
    private(set) var sizes: [SessionSize] = []

    init() throws {
        let (socket, peer) = try MessageConnection.makePair()
        self.peer = peer
        connection = ClientConnection(connection: socket)
        try peer.greetSessionProcess()
    }

    deinit {
        peer.shutdown()
    }

    func attach(to session: Session, size: SessionSize) async throws {
        guard case .attached = try await session.attach(connection, size: size, relaysRawOutput: false, receivesSizeChanges: true, waitsForOutputRoom: false),
              case .attached = try peer.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(10))),
              case .snapshot(let bytes) = try peer.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(10)))
        else { throw SessionProtocolError.unexpectedMessage(description: "The viewer did not attach.") }
        screen = try TerminalSnapshot(bytes: Array(bytes)).restoreTerminal(scrollbackLimit: Session.scrollbackLimit)
    }

    /// Takes messages until the screen shows the text, or until none came
    /// for the quiet time when the text is nil.
    @discardableResult
    func follow(until text: String? = nil, quiet: Duration = .seconds(10), once: Bool = false) throws -> Bool {
        var taken = 0
        while true {
            if once && taken == 1 { return true }
            taken += 1
            if let text, try self.text().contains(text) { return true }
            let message: ServerMessage?
            do {
                message = try peer.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + quiet))
            } catch SessionProtocolError.timedOut {
                return text == nil
            }
            switch message {
            case .output(let bytes): screen?.write(bytes)
            case .sizeChanged(let size, let keepsCursorAtLineStart, let promptRows):
                sizes.append(size)
                let keeping: PromptKeeping = promptRows.map { .promptRows(aboveCursor: $0) } ?? (keepsCursorAtLineStart == true ? .cursorRow : .nothing)
                try screen?.resize(to: TerminalSize(columns: size.columns, rows: size.rows), keeping: keeping)
            case nil: return false
            default: break
            }
        }
    }

    /// Takes messages while the condition holds, until the time limit. One
    /// time limit for all, so a wait never ends in the middle of a frame.
    func follow(while condition: () throws -> Bool, within limit: Duration) throws {
        let deadline = ContinuousClock.now + limit
        while try condition() {
            guard ContinuousClock.now < deadline, try follow(until: nil, quiet: deadline - .now, once: true) else { return }
        }
    }

    /// The screen and the scrollback, without the line ends of wrapped rows.
    func text() throws -> String {
        guard let screen else { return "" }
        return String(decoding: try screen.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
    }
}

/// An interactive bash without its line editor. Its prompt turns on
/// bracketed paste, so the session waits for an answer that never comes.
private func makeSilentShell(size: SessionSize, answerTimeLimit: Duration) throws -> Session {
    try makeSession(
        "/bin/bash", ["--noediting", "--norc", "-i"],
        environment: ["PATH": "/usr/bin:/bin", "PS1": "\u{1b}[?2004hready> ", "TERM": "xterm-256color"],
        size: size, answerTimeLimit: answerTimeLimit
    )
}

private func makeSession(_ executable: String, _ arguments: [String], environment: [String: String], size: SessionSize, answerTimeLimit: Duration = .milliseconds(500)) throws -> Session {
    try Session(
        summary: SessionSummary(identifier: UUID(), folder: "/", command: [executable] + arguments, size: size, createdAt: Date()),
        launch: ProgramLaunch(executablePath: executable, arguments: arguments, folder: "/", environment: environment,
                              size: PseudoTerminalSize(columns: size.columns, rows: size.rows)),
        onFinish: { _ in },
        answerTimeLimit: answerTimeLimit
    )
}

extension SessionProcessIntegration {
    @Suite struct LineEditorResizeTests {
        /// zsh counts the rows of its input at the old width when it draws
        /// it again. The output above the prompt must stay, and the prompt
        /// must appear once, on the session's screen and on the viewer's.
        /// Output without a line end puts the prompt on a row that continues
        /// that output. Behind another program, as behind ssh, zsh is not in
        /// the foreground, and only its output shows its prompt.
        @Test(arguments: [["/bin/zsh", "-f", "-i"], ["/bin/bash", "-c", "PS1='ready> ' /bin/zsh -f -i +m; true"]])
        func zshKeepsTheOutputAndOnePromptThroughManyWidths(command: [String]) async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try makeSession(command[0], Array(command.dropFirst()), environment: ["PATH": "/usr/bin:/bin", "PS1": "ready> ", "TERM": "xterm-256color"], size: size)
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            // The plain text leaves out the spaces at the end of a row.
            #expect(try viewer.follow(until: "ready>"))
            try await session.type(Array("printf 'output-before-resize\\n'\r".utf8))
            #expect(try viewer.follow(until: "output-before-resize\nready>"))
            try await session.type(Array("printf partial-output\r".utf8))
            #expect(try viewer.follow(until: "partial-output%"))
            try await session.type(Array(("echo " + String(repeating: "y", count: 150)).utf8))
            #expect(try viewer.follow(until: String(repeating: "y", count: 70)))
            try viewer.follow(quiet: .milliseconds(300))
            let original = try viewer.text().replacingOccurrences(of: "\n", with: "")

            // Every second resize comes while the one before it waits.
            for (index, columns) in [50, 30, 70, 40, 90, 45, 80].enumerated() {
                try await session.resize(to: SessionSize(columns: UInt16(columns), rows: 24), from: viewer.connection, confirmsResize: true)
                if index.isMultiple(of: 2) { try viewer.follow(quiet: .milliseconds(150)) }
            }
            try viewer.follow(quiet: .milliseconds(800))
            #expect(viewer.screen?.size == TerminalSize(columns: 80, rows: 24))
            #expect(try viewer.text().replacingOccurrences(of: "\n", with: "") == original)
            #expect(try await session.screenText(includeScrollback: true) == viewer.text())
            await session.terminate()
        }

        /// zsh draws its prompt again only after it has expanded it, and a
        /// command substitution in the prompt can take longer than the time
        /// limit. The screens then keep the rows of the prompt, and the late
        /// answer lands on them.
        @Test func aSlowPromptLandsOnItsRowsAfterTheTimeLimit() async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let environment = ["PATH": "/usr/bin:/bin", "PS1": "$(sleep 0.7)ready> ", "TERM": "xterm-256color"]
            let session = try makeSession("/bin/zsh", ["-f", "-o", "promptsubst", "-i"], environment: environment, size: size, answerTimeLimit: .milliseconds(300))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            try await session.type(Array("printf 'output-before-resize\\n'\r".utf8))
            #expect(try viewer.follow(until: "output-before-resize\nready>"))
            try await session.type(Array(("echo " + String(repeating: "y", count: 150)).utf8))
            #expect(try viewer.follow(until: String(repeating: "y", count: 70)))
            try viewer.follow(quiet: .milliseconds(300))
            let original = try viewer.text().replacingOccurrences(of: "\n", with: "")
            for columns: UInt16 in [50, 100, 30] {
                try await session.resize(to: SessionSize(columns: columns, rows: 24), from: viewer.connection, confirmsResize: true)
                try viewer.follow(quiet: .milliseconds(1500))
            }
            #expect(try viewer.text().replacingOccurrences(of: "\n", with: "") == original)
            #expect(try await session.screenText(includeScrollback: true) == viewer.text())
            await session.terminate()
        }

        /// A shell that is busy with its prompt answers a second size only
        /// after its late answer to the first, and that answer is for the
        /// first size. This script draws as zsh does, 0.7 s after a size. A
        /// newer size must wait for the late answer. Otherwise that answer
        /// ends the newer wait, and the screen takes the newer width under a
        /// prompt that the shell drew for the older one.
        @Test func aNewerSizeWaitsForTheLateAnswerOfTheOlderOne() async throws {
            let script = """
            stty raw -echo
            line="echo \(String(repeating: "y", count: 150))"
            above=0
            draw() {
              printf '\\r'; [ $above -gt 0 ] && printf '\\033[%dA' $above
              printf '\\033[0m\\033[27m\\033[24m\\033[Jready> %s' "$line"
              above=$(( (7 + ${#line} - 1) / $1 ))
            }
            columns() { stty size | cut -d' ' -f2; }
            printf 'output\\r\\n\\033[?2004h'; draw $(columns)
            trap 'width=$(columns); sleep 0.7; draw $width' WINCH
            while :; do sleep 0.05; done
            """
            let size = SessionSize(columns: 80, rows: 24)
            // The answer must come after the limit, and before 5 times the
            // limit, when the session stops the wait. With 300 ms, a busy Mac
            // sent the answer after 1.5 s. The limit of 500 ms, as in the
            // product, gives the late answer until 2.5 s.
            let session = try makeSession("/bin/bash", ["-c", script], environment: ["PATH": "/usr/bin:/bin"], size: size, answerTimeLimit: .milliseconds(500))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            #expect(try viewer.follow(until: String(repeating: "y", count: 70)))
            try viewer.follow(quiet: .milliseconds(300))
            let original = try viewer.text().replacingOccurrences(of: "\n", with: "")
            for columns: UInt16 in [100, 30] {
                try await session.resize(to: SessionSize(columns: columns, rows: 24), from: viewer.connection, confirmsResize: true)
                try await Task.sleep(for: .milliseconds(100))
            }
            // A busy Mac drew the last prompt more than 2 s late, so the test
            // waits for it. A prompt drawn at the wrong width stays wrong.
            try viewer.follow(while: { try viewer.sizes.count < 2 || viewer.text().replacingOccurrences(of: "\n", with: "") != original }, within: .seconds(30))
            try viewer.follow(quiet: .milliseconds(2000))
            #expect(viewer.sizes == [SessionSize(columns: 100, rows: 24), SessionSize(columns: 30, rows: 24)])
            #expect(try viewer.text().replacingOccurrences(of: "\n", with: "") == original)
            #expect(try await session.screenText(includeScrollback: true) == viewer.text())
            await session.terminate()
        }

        /// zsh writes its erase and its new lines together. When the erase
        /// ends a wait, the resize that waited starts in the same output, so
        /// the rest of it is older than that size. The session must skip it
        /// once, and then see zsh's answer to that size.
        @Test func theResizeThatWaitedGetsTheAnswerOfZsh() async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try makeSession("/bin/zsh", ["-f", "-i"], environment: ["PATH": "/usr/bin:/bin", "PS1": "ready> ", "TERM": "xterm-256color"],
                                          size: size, answerTimeLimit: .seconds(20))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            try await session.type(Array(("echo " + String(repeating: "y", count: 150)).utf8))
            #expect(try viewer.follow(until: String(repeating: "y", count: 70)))
            try viewer.follow(quiet: .milliseconds(300))
            let started = ContinuousClock.now
            for columns: UInt16 in [50, 30] {
                try await session.resize(to: SessionSize(columns: columns, rows: 24), from: viewer.connection, confirmsResize: true)
            }
            while viewer.sizes.count < 2, ContinuousClock.now - started < .seconds(5) { try viewer.follow(quiet: .milliseconds(100)) }
            #expect(viewer.sizes == [SessionSize(columns: 50, rows: 24), SessionSize(columns: 30, rows: 24)])
            #expect(ContinuousClock.now - started < .seconds(5))
            await session.terminate()
        }

        /// An interactive bash without its line editor never answers a new
        /// size. Its prompt turns on bracketed paste, so the session waits.
        /// The size applies after the time limit. Its answer is still due, so
        /// the resizes that came meanwhile wait four more time limits for it.
        /// Of them, only the newest applies.
        @Test func aSizeWithoutAnAnswerAppliesAfterTheTimeLimit() async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try makeSilentShell(size: size, answerTimeLimit: .milliseconds(300))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            #expect(try viewer.follow(until: "ready>"))

            let started = ContinuousClock.now
            for columns: UInt16 in [60, 70, 50] {
                try await session.resize(to: SessionSize(columns: columns, rows: 24), from: viewer.connection, confirmsResize: true)
            }
            try viewer.follow(quiet: .milliseconds(1800))
            #expect(viewer.sizes == [SessionSize(columns: 60, rows: 24), SessionSize(columns: 50, rows: 24)])
            #expect(ContinuousClock.now - started >= .milliseconds(1800))
            #expect(await session.summary.size == SessionSize(columns: 50, rows: 24))
            await session.terminate()
        }

        /// The program has the new size during the wait, so a size query
        /// gets that size, not the size of the session's screen.
        @Test func aSizeQueryDuringTheWaitGetsTheSizeOfTheProgram() async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try makeSilentShell(size: size, answerTimeLimit: .seconds(10))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            #expect(try viewer.follow(until: "ready>"))
            try await session.resize(to: SessionSize(columns: 60, rows: 24), from: viewer.connection, confirmsResize: true)
            let query = #"stty raw -echo; printf '\033[18t'; reply=$(dd bs=1 count=10 2>/dev/null); stty -raw echo; echo "REPLY=${reply:1}""#
            try await session.type(Array((query + "\r").utf8))
            #expect(try viewer.follow(until: "REPLY=["))
            let text = try viewer.text()
            #expect(text.contains("REPLY=[8;24;60t"), "\(text)")
            #expect(viewer.sizes.isEmpty)
            await session.terminate()
        }

        /// A bash that runs a script has no line editor, also when the script
        /// turns on bracketed paste. Its erase after a new size is not an
        /// answer, so the screen takes the size at once, as a terminal does.
        @Test func aScriptThatTurnsOnBracketedPasteGetsTheSizeAtOnce() async throws {
            let start = String(repeating: "A", count: 39)
            let script = """
            stty raw -echo opost
            trap 'printf "\\r\\033[KZ\\r\\nDONE\\r\\n"' WINCH
            printf '\\033[?2004hREADY\\r\\n\(start) X\\r\\033[K'
            while :; do sleep 0.05; done
            """
            let size = SessionSize(columns: 40, rows: 8)
            let session = try makeSession("/bin/bash", ["-c", script], environment: ["PATH": "/usr/bin:/bin"], size: size)
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            #expect(try viewer.follow(until: start))
            try await session.resize(to: SessionSize(columns: 80, rows: 8), from: viewer.connection, confirmsResize: true)
            #expect(try viewer.follow(until: "DONE"))
            #expect(viewer.sizes == [SessionSize(columns: 80, rows: 8)])
            #expect(try await session.screenText(includeScrollback: false) == "READY\nZ\nDONE")
            await session.terminate()
        }

        /// A size of zero changes nothing, so it must not replace a resize
        /// that waits. The model of `specifications/ResizeWait.tla` found it.
        @Test func aZeroSizeDuringTheWaitKeepsTheResizeThatWaits() async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try makeSilentShell(size: size, answerTimeLimit: .milliseconds(300))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            #expect(try viewer.follow(until: "ready>"))
            for (columns, confirms) in [(UInt16(60), true), (80, true), (0, false)] {
                try await session.resize(to: SessionSize(columns: columns, rows: 24), from: viewer.connection, confirmsResize: confirms)
            }
            try viewer.follow(quiet: .milliseconds(1800))
            #expect(viewer.sizes == [SessionSize(columns: 60, rows: 24), size])
            #expect(await session.summary.size == size)
            await session.terminate()
        }

        /// zsh with `-i` and a script is interactive, but it runs the script
        /// and edits no line. A script that turns on bracketed paste must get
        /// the size at once, not after the time limit of a wait.
        @Test func anInteractiveZshThatRunsAScriptGetsTheSizeAtOnce() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let script = folder.appendingPathComponent("bracketed-paste")
            // Only builtins run, so zsh itself stays in the foreground.
            try "printf '\\033[?2004hREADY\\n'\nwhile :; do read -t 1 line; done\n".write(to: script, atomically: true, encoding: .utf8)
            let size = SessionSize(columns: 40, rows: 8)
            let session = try makeSession("/bin/zsh", ["-f", "-i", script.path], environment: ["PATH": "/usr/bin:/bin"], size: size, answerTimeLimit: .seconds(10))
            await session.start()
            let viewer = try FollowingViewer()
            try await viewer.attach(to: session, size: size)
            #expect(try viewer.follow(until: "READY"))
            try await session.resize(to: SessionSize(columns: 80, rows: 8), from: viewer.connection, confirmsResize: true)
            try viewer.follow(quiet: .milliseconds(500))
            #expect(viewer.sizes == [SessionSize(columns: 80, rows: 8)])
            await session.terminate()
        }
    }
}
