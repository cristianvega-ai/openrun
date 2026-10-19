import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// Dense output must stay fast. The session process parses every byte
    /// that a program writes, so a slow terminal library shows up here first.
    /// The library is built in an optimized mode for this reason.
    ///
    /// The program numbers its lines. A test can then tell a run that parsed
    /// all of the output from a run that lost, repeated or reordered some of it.
    @Suite struct ThroughputTests {
        private static let lineCount = 250_000
        /// Six digits, a space, 56 printable characters and a line feed.
        private static let lineLength = 64
        private static let byteCount = lineCount * lineLength
        private static let timeLimit = Duration.seconds(5)
        private static let padding = "0123456789abcdef0123456789abcdef0123456789abcdef01234567"

        private static let writeCommand = "awk 'BEGIN { for (n = 1; n <= \(lineCount); n++) printf \"%06d \(padding)\\n\", n }'"

        private static func line(_ number: Int) -> String {
            String(format: "%06d ", number) + padding
        }

        /// The bytes that a client sees. The pseudo terminal turns every line
        /// feed into a carriage return and a line feed.
        private static func expectedOutput() -> Data {
            var expected = Data(capacity: lineCount * (lineLength + 1))
            for number in 1...lineCount {
                expected.append(contentsOf: (line(number) + "\r\n").utf8)
            }
            return expected
        }

        /// The pseudo terminal of macOS sometimes writes a second carriage
        /// return before a line break, when the reader is slower than the
        /// program. It happens with any reader, so it is not a fault of the
        /// session process. The extra byte is the only difference that the
        /// comparison forgives. A repeated, missing or moved line still shows.
        private static func removingRepeatedCarriageReturns(from bytes: Data) -> Data {
            var cleaned = [UInt8]()
            cleaned.reserveCapacity(bytes.count)
            for byte in bytes {
                if byte == 10, cleaned.count >= 2, cleaned[cleaned.count - 1] == 13, cleaned[cleaned.count - 2] == 13 {
                    cleaned.removeLast()
                }
                cleaned.append(byte)
            }
            return Data(cleaned)
        }

        @Test func sixteenMegabytesOfTextReachTheExitWithoutAClient() async throws {
            try await RunningSessionProcess.run { process in
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()

                let clock = ContinuousClock()
                let start = clock.now
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.writeCommand])
                let session = try #require(UUID(uuidString: identifier))
                // The session leaves the list as soon as its program has ended
                // and the session has parsed all of the output. Only a list
                // that no longer holds the session counts as the end. Any
                // other answer, a closed connection or a timeout is a failure.
                var elapsed = clock.now - start
                var ended = false
                while elapsed < .seconds(30) {
                    try connection.send(ClientMessage.listSessions)
                    guard let reply = try connection.receive(ServerMessage.self) else {
                        Issue.record("The session process closed the connection while the session was running.")
                        return
                    }
                    guard case .sessionList(let sessions) = reply else {
                        Issue.record("The answer to listSessions was \(reply), not a list of sessions.")
                        return
                    }
                    elapsed = clock.now - start
                    if !sessions.contains(where: { $0.identifier == session }) {
                        ended = true
                        break
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
                print("Throughput, no client: \(Self.byteCount) bytes reached the exit in \(elapsed)")
                #expect(ended, "The session was still listed after 30 seconds.")
                #expect(process.isRunning, "The session process died.")
                #expect(elapsed < Self.timeLimit)
            }
        }

        /// The first test cannot look at the screen, because the session is
        /// gone once the program ends. Here the program stays alive after its
        /// last line, so the screen can show that the session parsed every line
        /// up to the last one, in order, within the time limit.
        @Test func sixteenMegabytesOfTextAreParsedWithoutAClient() async throws {
            try await RunningSessionProcess.run { process in
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()

                let clock = ContinuousClock()
                let start = clock.now
                let identifier = try process.createSession(program: ["/bin/sh", "-c", Self.writeCommand + "; sleep 600"])
                let session = try #require(UUID(uuidString: identifier))
                let lastLine = Self.line(Self.lineCount)
                var screen = ""
                var elapsed = clock.now - start
                while elapsed < .seconds(30) {
                    try connection.send(ClientMessage.readScreen(identifier: session, includeScrollback: false))
                    guard let reply = try connection.receive(ServerMessage.self) else {
                        Issue.record("The session process closed the connection while the session was running.")
                        return
                    }
                    guard case .screen(let text) = reply else {
                        Issue.record("The answer to readScreen was \(reply), not a screen.")
                        return
                    }
                    screen = text
                    elapsed = clock.now - start
                    if screen.contains(lastLine) { break }
                    try await Task.sleep(for: .milliseconds(5))
                }
                print("Throughput, no client: the screen showed line \(Self.lineCount) after \(elapsed)")
                #expect(screen.contains(lastLine), "The last line never reached the screen.")
                #expect(elapsed < Self.timeLimit)

                // Every row of the screen must hold the right line. The last
                // line is on the screen, so the rows above it are the lines
                // right before it. A parser that skipped or repeated text
                // would break this run of numbers.
                let rows = screen.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                let expectedRows = (0..<rows.count).map { Self.line(Self.lineCount - rows.count + 1 + $0) }
                #expect(!rows.isEmpty)
                #expect(rows == expectedRows)
                #expect(process.isRunning, "The session process died.")
            }
        }

        @Test func sixteenMegabytesOfTextReachTheExitWithOneClientThatReadsAllOutput() async throws {
            let expected = Self.expectedOutput()
            try await RunningSessionProcess.run { process in
                // The program waits for a file, so the client is attached
                // before the first byte of output and sees all of it.
                let releaseFile = process.directory.appendingPathComponent("release").path
                let script = "while [ ! -e '\(releaseFile)' ]; do sleep 0.05; done; " + Self.writeCommand
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()
                try connection.send(ClientMessage.attach(
                    identifier: try #require(UUID(uuidString: identifier)),
                    size: SessionSize(columns: 80, rows: 24),
                    relaysRawOutput: true
                ))
                guard case .attached = try connection.receive(ServerMessage.self) else {
                    Issue.record("The first answer to attach was not attached.")
                    return
                }

                let clock = ContinuousClock()
                let start = clock.now
                FileManager.default.createFile(atPath: releaseFile, contents: Data())
                let rawReceived = try await Task.detached { try Self.readUntilExit(connection) }.value
                let elapsed = clock.now - start
                print("Throughput, one client: \(rawReceived.count) bytes reached the exit in \(elapsed)")
                let received = Self.removingRepeatedCarriageReturns(from: rawReceived)
                #expect(received.count == expected.count, "The client received \(received.count) bytes, not \(expected.count).")
                // The two streams must match byte for byte. This catches bytes
                // that arrive twice, in another order or with other values,
                // which a count alone does not.
                if received != expected {
                    let offset = zip(received, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(received.count, expected.count)
                    Issue.record("The output differs from the lines that the program wrote, first at byte \(offset).")
                }
                #expect(elapsed < Self.timeLimit)
            }
        }

        /// Reads every message, as fast as it arrives, until the program exits.
        /// Returns the output bytes in the order received.
        private static func readUntilExit(_ connection: MessageConnection) throws -> Data {
            var received = Data()
            received.reserveCapacity(byteCount + lineCount)
            while let message = try connection.receive(ServerMessage.self) {
                switch message {
                case .snapshot:
                    continue
                case .output(let bytes):
                    received.append(bytes)
                case .exited:
                    return received
                default:
                    continue
                }
            }
            throw ThroughputError.connectionClosedBeforeExit
        }

        private enum ThroughputError: Error {
            case connectionClosedBeforeExit
        }
    }
}
