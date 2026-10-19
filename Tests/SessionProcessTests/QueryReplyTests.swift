import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

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

        /// The colors that the macOS appearance gives: black on white in light
        /// mode, white on black in dark mode. The test cannot tell which mode
        /// the Mac is in, so it accepts only the two matching pairs.
        private static func expectColors(in screen: String) {
            let light = screen.contains("foreground=033]10;rgb:0000/0000/0000\\a") && screen.contains("background=033]11;rgb:ffff/ffff/ffff\\a")
            let dark = screen.contains("foreground=033]10;rgb:ffff/ffff/ffff\\a") && screen.contains("background=033]11;rgb:0000/0000/0000\\a")
            #expect(light || dark, "colors: \(screen)")
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
                Self.expectColors(in: try process.screenText(of: identifier).filter { !$0.isWhitespace })
            }
        }

        @Test func aReplyThatArrivesOneSecondLateIsSeenByTheDuplicateDetector() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.script(goFolder: process.directory)])
                #expect(await process.waitForScreen(of: identifier, containing: "READY"))
                Self.releaseProgram(in: process.directory, round: 1)
                #expect(await process.waitForScreen(of: identifier, containing: Self.expectedReply))
                // The program has read its reply and now listens for a second
                // one. These two bytes play a late duplicate.
                try await Task.sleep(for: .seconds(1))
                _ = try process.runCommand(["send", identifier, "ZZ"])
                #expect(await process.waitForScreen(of: identifier, containing: "DONE1"))
                #expect(try process.screenText(of: identifier).contains("extra1=2"))
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
