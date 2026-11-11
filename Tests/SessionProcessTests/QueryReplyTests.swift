import Foundation
import PseudoTerminal
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionProcess

extension SessionProcessIntegration {
    /// Each terminal query must get exactly one reply. The session process
    /// answers when no real terminal does. While a client that relays raw
    /// output is attached, that client's terminal window answers instead.
    @Suite struct QueryReplyTests {
        /// The reply to a device attributes query, as `od -c` shows it.
        private static let expectedReply = "033   [   ?   6   2   ;   2   2   c"

        /// The program asks "what are you" (a device attributes query) once for
        /// each go file that appears. It reads the reply byte by byte, then
        /// listens a little longer for a second reply. A test creates a go file
        /// when it has set up the clients it wants to have at that moment.
        private static func script(goFolder: URL) -> String {
            """
            stty raw -echo opost
            round() {
              while [ ! -e '\(goFolder.path)'/"$1" ]; do sleep 0.1; done
              printf '\\033[c'
              printf 'reply%s=' "$1"
              dd bs=1 count=9 2>/dev/null | od -An -c
              stty min 0 time 20
              printf 'extra%s=%s\\n' "$1" "$(dd bs=1 count=64 2>/dev/null | wc -c | tr -d ' ')"
              stty min 1 time 0
              printf 'DONE%s\\n' "$1"
            }
            printf 'READY\\n'
            round 1
            round 2
            sleep 60
            """
        }

        private static func releaseProgram(in folder: URL, round: Int) {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("\(round)").path, contents: Data())
        }

        private static func attach(to identifier: String, of process: RunningSessionProcess) throws -> AttachedTerminal {
            let executable = RunningSessionProcess.commandExecutable.path
            return try AttachedTerminal(
                shellScript: "'\(executable)' attach \(identifier) --socket '\(process.socketPath)'",
                folder: process.directory
            )
        }

        @Test func aDeviceAttributesQueryIsAnsweredOnceWithoutAClient() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                Self.releaseProgram(in: process.directory, round: 1)
                #expect(await process.waitForScreen(of: identifier, containing: "DONE1"))
                let screen = try process.screenText(of: identifier)
                #expect(screen.contains(Self.expectedReply))
                #expect(screen.contains("extra1=0"))
            }
        }

        @Test func aDeviceAttributesQueryIsAnsweredOnceByTheRealTerminalOfAnAttachedClient() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                let attached = try Self.attach(to: identifier, of: process)
                defer { attached.closeNow() }
                // The snapshot shows READY, and the session registered the
                // client in the same step that it took the snapshot.
                #expect(await attached.waitForScreen(containing: "READY"))
                Self.releaseProgram(in: process.directory, round: 1)
                #expect(await attached.waitForScreen(containing: "DONE1"))
                let screen = attached.screenText
                #expect(screen.contains(Self.expectedReply))
                #expect(screen.contains("extra1=0"))
                // The window answered, so the session process stayed silent.
                #expect(attached.repliesSent == 1)
            }
        }

        @Test func theSessionProcessAnswersAgainAfterTheRelayingClientDetaches() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                let attached = try Self.attach(to: identifier, of: process)
                defer { attached.closeNow() }
                #expect(await attached.waitForScreen(containing: "READY"))
                Self.releaseProgram(in: process.directory, round: 1)
                #expect(await attached.waitForScreen(containing: "DONE1"))

                attached.type(bytes: [0x1D])
                #expect(await attached.waitForExit() != nil)
                Self.releaseProgram(in: process.directory, round: 2)
                #expect(await process.waitForScreen(of: identifier, containing: "DONE2"))
                let screen = try process.screenText(of: identifier)
                #expect(screen.contains("extra1=0"))
                #expect(screen.contains("reply2="))
                #expect(screen.contains(Self.expectedReply))
                #expect(screen.contains("extra2=0"))
                // The window answered round 1 only. It was gone for round 2.
                #expect(attached.repliesSent == 1)
            }
        }

        @Test func aClientThatAttachesAfterTheAnswerDoesNotAnswerAgain() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                Self.releaseProgram(in: process.directory, round: 1)
                #expect(await process.waitForScreen(of: identifier, containing: "DONE1"))

                // The snapshot holds the screen and not the bytes of the query.
                let attached = try Self.attach(to: identifier, of: process)
                defer { attached.closeNow() }
                #expect(await attached.waitForScreen(containing: "DONE1"))
                #expect(attached.screenText.contains(Self.expectedReply))
                #expect(attached.repliesSent == 0)
                #expect(try process.screenText(of: identifier).contains("extra1=0"))
            }
        }

        @Test func aClientThatDoesNotSayItRelaysIsAnsweredForLikeNoClient() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                // A client of the first release of protocol version 1 sends an
                // attach message without the relay field.
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()
                let message = #"{"attach":{"identifier":"\#(identifier.uppercased())","size":{"columns":80,"rows":24}}}"#
                try connection.send(ControlMessage(text: message))
                guard case .attached = try connection.receive(ServerMessage.self) else {
                    Issue.record("The first answer to attach was not attached.")
                    return
                }
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                Self.releaseProgram(in: process.directory, round: 1)
                #expect(await process.waitForScreen(of: identifier, containing: "DONE1"))
                let screen = try process.screenText(of: identifier)
                #expect(screen.contains(Self.expectedReply))
                #expect(screen.contains("extra1=0"))
            }
        }

        /// The program asks the three queries that a headless session once left
        /// unanswered. After each reply it listens for a second one.
        private static let sizeAndSchemeScript = #"""
        stty raw -echo opost
        ask() {
          printf "$2"
          printf '%s=' "$1"
          dd bs=1 count=$3 2>/dev/null | od -An -c
          stty min 0 time 15
          printf 'extra_%s=%s\n' "$1" "$(dd bs=1 count=64 2>/dev/null | wc -c | tr -d ' ')"
          stty min 1 time 0
        }
        printf 'size=%s\n' "$(stty size)"
        ask characters '\033[18t' 10
        ask area '\033[14t' 12
        ask scheme '\033[?996n' 9
        printf 'DONE\n'
        sleep 60
        """#

        @Test func sizeAndColorSchemeQueriesAreAnsweredOnceWithoutAClient() async throws {
            try await RunningSessionProcess.run { process in
                // No client ever attaches to this session.
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.sizeAndSchemeScript])
                #expect(await process.waitForScreen(of: identifier, containing: "DONE", timeout: .seconds(30)))
                // od separates bytes with spaces, and long lines may wrap.
                let screen = try process.screenText(of: identifier).filter { !$0.isWhitespace }
                // The new session has the size of a plain 80 by 24 window.
                #expect(screen.contains("size=2480"))
                // CSI 18 t: ESC [ 8 ; 24 ; 80 t
                #expect(screen.contains("characters=033[8;24;80t"))
                #expect(screen.contains("extra_characters=0"))
                // CSI 14 t: 24 rows of 16 pixels, 80 columns of 8 pixels.
                #expect(screen.contains("area=033[4;384;640t"))
                #expect(screen.contains("extra_area=0"))
                // CSI ? 996 n: dark is 1 and light is 2.
                #expect(screen.contains("scheme=033[?997;1n") || screen.contains("scheme=033[?997;2n"))
                #expect(screen.contains("extra_scheme=0"))
            }
        }

        /// The program asks for the foreground color, the background color, and
        /// the size of the screen in pixels (12 bytes of reply). These sit outside the first set of
        /// queries. After each reply it listens for a second one. A go file
        /// lets a test attach a client first.
        private static func colorAndDotSizeScript(goFolder: URL) -> String {
            #"""
            stty raw -echo opost
            ask() {
              printf "$2"
              printf '%s=' "$1"
              dd bs=1 count=$3 2>/dev/null | od -An -c
              stty min 0 time 15
              printf 'extra_%s=%s\n' "$1" "$(dd bs=1 count=64 2>/dev/null | wc -c | tr -d ' ')"
              stty min 1 time 0
            }
            printf 'READY\n'
            while [ ! -e '\#(goFolder.path)'/go ]; do sleep 0.1; done
            ask foreground '\033]10;?\007' 24
            ask background '\033]11;?\007' 24
            ask dots '\033[15t' 12
            printf 'DONE\n'
            sleep 60
            """#
        }

        /// The answers of the session process: the Graphite colors of the macOS appearance, light then dark.
        private static let graphitePairs = [("1e1e/2020/2222", "fafa/fbfb/fcfc"), ("e6e6/eeee/f4f4", "1e1e/2020/2222")]
        /// The answers of the terminal of the harness, which plays the window: black on white or white on black.
        private static let plainPairs = [("0000/0000/0000", "ffff/ffff/ffff"), ("ffff/ffff/ffff", "0000/0000/0000")]

        /// The test cannot tell which mode the Mac is in, so it accepts only
        /// the two matching pairs.
        private static func expectColors(in screen: String, from pairs: [(String, String)]) {
            let matches = pairs.contains { screen.contains("foreground=033]10;rgb:\($0.0)\\a") && screen.contains("background=033]11;rgb:\($0.1)\\a") }
            #expect(matches, "colors: \(screen)")
            // A 80 by 24 grid of 8 by 16 pixel cells: 384 high and 640 wide.
            #expect(screen.contains("dots=033[5;384;640t"))
            for name in ["foreground", "background", "dots"] {
                #expect(screen.contains("extra_\(name)=0"), "extra_\(name): \(screen)")
            }
        }

        @Test func colorAndDotSizeQueriesAreAnsweredOnceWithoutAClient() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.colorAndDotSizeScript(goFolder: process.directory)])
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                FileManager.default.createFile(atPath: process.directory.appendingPathComponent("go").path, contents: Data())
                #expect(await process.waitForScreen(of: identifier, containing: "DONE", timeout: .seconds(30)))
                Self.expectColors(in: try process.screenText(of: identifier).filter { !$0.isWhitespace }, from: Self.graphitePairs)
            }
        }

        @Test func colorAndDotSizeQueriesAreAnsweredOnlyByTheRealTerminalOfAnAttachedClient() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.colorAndDotSizeScript(goFolder: process.directory)])
                let attached = try Self.attach(to: identifier, of: process)
                defer { attached.closeNow() }
                #expect(await attached.waitForScreen(containing: "READY"))
                FileManager.default.createFile(atPath: process.directory.appendingPathComponent("go").path, contents: Data())
                #expect(await attached.waitForScreen(containing: "DONE", timeout: .seconds(30)))
                Self.expectColors(in: attached.screenText.filter { !$0.isWhitespace }, from: Self.plainPairs)
                // One answer for each of the three queries, all from the window.
                #expect(attached.repliesSent == 3)
            }
        }

        /// The program asks for the foreground, background and cursor colors
        /// and for colors 0 to 15, and prints the answers with ESC as E and BEL as B.
        private static let paletteScript = #"""
        stty raw -echo opost min 0 time 10
        printf '\033]10;?\007\033]11;?\007\033]12;?\007'
        for index in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do printf '\033]4;%d;?\007' $index; done
        printf 'answers=%s\n' "$(dd bs=1 count=2000 2>/dev/null | tr '\033\007' EB)"
        printf 'DONE\n'
        sleep 60
        """#

        /// The table "Graphite theme" of `documentation/product.md`: the text,
        /// the background, the cursor and colors 0 to 15.
        private static let graphiteLight = "1e2022 fafbfc 1e2022 1e2022 b8364b 327339 81600e 2b67b1 8748bc 137073 d6dade 6e7277 ce3b53 3d8044 8f6c15 3073c5 9553cb 197e80 f3f4f6"
        private static let graphiteDark = "e6eef4 1e2022 e6eef4 2e3134 e87382 9fcb8b e2c27f 79aee6 c59de6 67c9cb c8cfd5 8a8f94 f08f9b b4d8a3 ebd29b 97c1ee d5b5ee 88d8d9 e6eef4"

        private static func answers(_ colors: String) -> String {
            zip(["10", "11", "12"] + (0..<16).map { "4;\($0)" }, colors.split(separator: " ")).map { name, color in
                "E]\(name);rgb:\([0, 2, 4].map { String(repeating: String(color.dropFirst($0).prefix(2)), count: 2) }.joined(separator: "/"))B"
            }.joined()
        }

        @Test func theSessionProcessAnswersWithTheGraphiteColorsOfTheAppearance() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.paletteScript])
                #expect(await process.waitForScreen(of: identifier, containing: "DONE"))
                let screen = try process.screenText(of: identifier).filter { !$0.isWhitespace }
                #expect([Self.graphiteLight, Self.graphiteDark].contains { screen.contains("answers=" + Self.answers($0)) }, "\(screen)")
            }
        }

        @Test(arguments: [TerminalColorScheme.light, .dark])
        func aSessionAnswersWithTheGraphiteVersionOfItsScheme(scheme: TerminalColorScheme) async throws {
            let size = SessionSize(columns: 80, rows: 24)
            let session = try Session(
                summary: SessionSummary(identifier: UUID(), folder: "/", command: ["/bin/sh"], size: size, createdAt: Date()),
                launch: ProgramLaunch(executablePath: "/bin/sh", arguments: ["-c", Self.paletteScript], folder: "/", environment: ["PATH": "/usr/bin:/bin"],
                                      size: PseudoTerminalSize(columns: size.columns, rows: size.rows)),
                onFinish: { _ in }) { try Session.installReplies(on: $0, handler: $1, colorScheme: { scheme }) }
            await session.start()
            #expect(await eventually { (try? await session.screenText(includeScrollback: false))?.contains("DONE") == true })
            let screen = try await session.screenText(includeScrollback: false).filter { !$0.isWhitespace }
            #expect(screen.contains("answers=" + Self.answers(scheme == .dark ? Self.graphiteDark : Self.graphiteLight)), "\(screen)")
            await session.terminate()
        }

        @Test func aReplyThatArrivesOneSecondLateIsSeenByTheDuplicateDetector() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                // The connection opens before the program listens. Starting
                // the `openrun send` program inside the two second window
                // could take longer than the window on a busy computer.
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.close() }
                try connection.greetSessionProcess()
                Self.releaseProgram(in: process.directory, round: 1)
                // The test looks at the screen through its open connection.
                // `openrun read` starts a program for each look, which on a busy
                // computer took most of a second, and the bytes came after the
                // window of two seconds.
                let session = try #require(UUID(uuidString: identifier))
                #expect(await eventually(timeout: .seconds(60)) {
                    try? connection.send(ClientMessage.readScreen(identifier: session, includeScrollback: false))
                    guard case .screen(let text) = try? connection.receive(ServerMessage.self) else { return false }
                    return text.contains(Self.expectedReply)
                })
                // The program has read its reply and now listens for a second
                // one. These two bytes play a late duplicate.
                try await Task.sleep(for: .seconds(1))
                try connection.send(ClientMessage.sendText(identifier: session, text: "ZZ"))
                #expect(await process.waitForScreen(of: identifier, containing: "DONE1"))
                #expect(try process.screenText(of: identifier).contains("extra1=2"))
            }
        }

        /// The program turns on the in-band size reports of mode 2048 and
        /// reads the report that comes at once. After the go file, it prints
        /// the reports that came later, with ESC as E.
        private static func sizeReportScript(goFolder: URL) -> String {
            #"""
            stty raw -echo opost min 0 time 10
            printf '\033[?2048h'
            dd bs=1 count=20 >/dev/null 2>&1
            printf 'READY\n'
            while [ ! -e '\#(goFolder.path)'/go ]; do sleep 0.1; done
            stty time 20
            printf 'reports=%s\n' "$(dd bs=1 count=200 2>/dev/null | tr '\033' E)"
            printf 'DONE\n'
            sleep 60
            """#
        }

        /// Attaches over the protocol and waits for `attached`.
        private static func attach(to session: UUID, of process: RunningSessionProcess, size: SessionSize, relaysRawOutput: Bool?) throws -> MessageConnection {
            let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
            try connection.greetSessionProcess()
            try connection.send(ClientMessage.attach(identifier: session, size: size, relaysRawOutput: relaysRawOutput))
            guard case .attached = try connection.receive(ServerMessage.self) else {
                throw HarnessError.commandFailed(description: "The attach was not answered with attached.")
            }
            return connection
        }

        /// Sends a resize and returns once the session has handled it. The
        /// answer to the list request behind it comes only after that.
        private static func resize(_ connection: MessageConnection, to size: SessionSize) throws {
            try connection.send(ClientMessage.resize(size))
            try connection.send(ClientMessage.listSessions)
            while let message = try connection.receive(ServerMessage.self) {
                if case .sessionList = message { return }
            }
        }

        /// A relaying client kept the replies
        /// closed, so a size change by another client sent no report of mode
        /// 2048. The relaying client's own resize is for its terminal to report.
        @Test func eachSizeChangeIsReportedOnceWhileARelayingClientIsAttached() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.sizeReportScript(goFolder: process.directory)])
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                let session = try #require(UUID(uuidString: identifier))
                let relaying = try Self.attach(to: session, of: process, size: SessionSize(columns: 80, rows: 24), relaysRawOutput: true)
                defer { relaying.shutdown() }
                let other = try Self.attach(to: session, of: process, size: SessionSize(columns: 100, rows: 30), relaysRawOutput: nil)
                defer { other.shutdown() }
                try Self.resize(other, to: SessionSize(columns: 120, rows: 40))
                try Self.resize(relaying, to: SessionSize(columns: 90, rows: 25))

                FileManager.default.createFile(atPath: process.directory.appendingPathComponent("go").path, contents: Data())
                #expect(await process.waitForScreen(of: identifier, containing: "DONE"))
                let screen = try process.screenText(of: identifier)
                #expect(screen.contains("reports=E[48;30;100;480;800tE[48;40;120;640;960t\n"), "screen: \(screen)")
            }
        }

        @Test func aCursorPositionQueryReportsTheCursor() async throws {
            try await RunningSessionProcess.run { process in
                let script = "stty raw -echo opost; printf 'abc\\n\\033[6n'; dd bs=1 count=6 2>/dev/null | od -An -c; echo DONE; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "DONE"))
                // Row 2, column 1 after "abc" and a newline: ESC [ 2 ; 1 R.
                #expect(try process.screenText(of: identifier).contains("033   [   2   ;   1   R"))
            }
        }
    }
}

/// A control message with text that a test wrote by hand, as an older client
/// would send it.
private struct ControlMessage: FramedMessage {
    let text: String

    init(text: String) {
        self.text = text
    }

    func frame() throws -> MessageFrame {
        MessageFrame(kind: .control, payload: Data(text.utf8))
    }

    init(frame: MessageFrame) throws {
        text = String(decoding: frame.payload, as: UTF8.self)
    }
}
