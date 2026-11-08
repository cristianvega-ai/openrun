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
