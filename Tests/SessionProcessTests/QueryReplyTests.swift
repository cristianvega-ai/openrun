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
