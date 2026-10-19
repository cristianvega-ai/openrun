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
    }
}
