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
    func follow(until text: String? = nil, quiet: Duration = .seconds(10)) throws -> Bool {
        while true {
            if let text, try self.text().contains(text) { return true }
            let message: ServerMessage?
            do {
                message = try peer.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + quiet))
            } catch SessionProtocolError.timedOut {
                return text == nil
            }
            switch message {
            case .output(let bytes): screen?.write(bytes)
            case .sizeChanged(let size, let keepsCursorAtLineStart):
                sizes.append(size)
                try screen?.resize(to: TerminalSize(columns: size.columns, rows: size.rows), keepingCursorAtLineStart: keepsCursorAtLineStart == true)
            case nil: return false
            default: break
            }
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
        /// An interactive bash without its line editor never answers a new
        /// size. Its prompt turns on bracketed paste, so the session waits.
        /// The size applies after the time limit, and of the resizes that
        /// came meanwhile only the newest applies.
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
            try viewer.follow(quiet: .milliseconds(900))
            #expect(viewer.sizes == [SessionSize(columns: 60, rows: 24), SessionSize(columns: 50, rows: 24)])
            #expect(ContinuousClock.now - started >= .milliseconds(600))
            #expect(await session.summary.size == SessionSize(columns: 50, rows: 24))
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
            try viewer.follow(quiet: .milliseconds(1200))
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
