import Foundation
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing

extension SessionProcessIntegration {
    /// With mode 2027, a terminal gives an emoji with U+FE0F two cells. The
    /// zsh of macOS counts such an emoji as one column. With the mode on, the
    /// two disagree, and zsh loses letters where a line wraps (the run of
    /// 2026-10-27 in the evidence of U8). So the sessions keep the mode off,
    /// and this test fails when a change turns it on.
    @Suite struct GraphemeClusterSessionTests {
        private static let size = SessionSize(columns: 20, rows: 6)

        /// The terminal of the session, as a client restores it from a snapshot.
        private static func sessionTerminal(_ session: UUID, of process: RunningSessionProcess) throws -> Terminal {
            let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
            defer { connection.shutdown() }
            try connection.greetSessionProcess()
            try connection.send(ClientMessage.attach(identifier: session, size: size))
            guard case .attached = try connection.receive(ServerMessage.self), case .snapshot(let bytes) = try connection.receive(ServerMessage.self) else {
                throw HarnessError.commandFailed(description: "The attach gave no snapshot.")
            }
            return try TerminalSnapshot(bytes: Array(bytes)).restoreTerminal(scrollbackLimit: 100)
        }

        /// The text of each cell of the first row.
        private static func firstRow(of terminal: Terminal) throws -> [String] {
            let state = try RenderState()
            try state.update(from: terminal)
            var cells: [String] = []
            try state.forEachRow(onlyChanged: false) { row in
                if row.viewportRow == 0 { try row.forEachCell(palette: state.colors.palette) { cells.append($0.text) } }
            }
            return cells
        }

        @Test func zshAndTheSessionPutTheCursorInTheSameColumnAfterAnEmojiPrompt() async throws {
            try await RunningSessionProcess.run { process in
                let home = try RunningSessionProcess.makeDirectory()
                defer { try? FileManager.default.removeItem(at: home) }
                try "PROMPT=$'\\u2764\\uFE0F '\n".write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()
                let environment = ProcessInfo.processInfo.environment.merging(["ZDOTDIR": home.path]) { $1 }
                try connection.send(ClientMessage.createSession(folder: home.path, command: ["/bin/zsh", "-i"], size: Self.size, environment: environment))
                guard case .sessionCreated(let summary) = try connection.receive(ServerMessage.self) else { throw HarnessError.commandFailed(description: "No session.") }
                let identifier = summary.identifierText
                #expect(await process.waitForScreen(of: identifier, containing: "\u{2764}\u{FE0F}"))

                // The line wraps at 20 columns. The cursor then goes back 10 letters, before the wrap.
                _ = try process.runCommand(["send", identifier, "abcdefghijklmnopqrstuvwxy"])
                #expect(await process.waitForScreen(of: identifier, containing: "stuvwxy"))
                _ = try process.runCommand(["send", identifier, String(repeating: "\u{1B}[D", count: 10) + "XY"])
                #expect(await process.waitForScreen(of: identifier, containing: "XY"))
                let before = try Self.sessionTerminal(summary.identifier, of: process)
                #expect(!before.isModeEnabled(.graphemeClusters))

                // zsh draws the next letter where the terminal of the session has its cursor.
                _ = try process.runCommand(["send", identifier, "Z"])
                #expect(await process.waitForScreen(of: identifier, containing: "XYZ"))
                let row = try Self.firstRow(of: Self.sessionTerminal(summary.identifier, of: process))
                let column = Int(before.cursorPosition.column)
                #expect(before.cursorPosition.row == 0 && row.dropFirst(column).first == "Z", "\(row)")
                #expect(try process.screenText(of: identifier) == "\u{2764}\u{FE0F} abcdefghijklmnoXYZ\npqrstuvwxy\n")
            }
        }
    }
}
