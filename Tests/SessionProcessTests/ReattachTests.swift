import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
import TerminalEmulation

/// Runs `body` and shuts the connection down when it takes longer than
/// `limit`, so a regression makes a test fail instead of hanging `swift test`.
/// Returns whether the limit passed.
private func withTimeLimit<Result>(_ limit: TimeInterval, on connection: MessageConnection, _ body: () throws -> Result) rethrows -> (result: Result, timedOut: Bool) {
    let didTimeOut = Mutex(false)
    let watchdog = DispatchWorkItem {
        didTimeOut.withLock { $0 = true }
        connection.shutdown()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    let result = try body()
    return (result, didTimeOut.withLock { $0 })
}

/// A client written against the socket protocol alone. It sees the exact
/// frames, so tests can check the snapshot and the output after it. Every
/// wait has a time limit.
private final class ProtocolClient {
    let connection: MessageConnection
    let terminal: Terminal
    /// The bytes of the escape sequence or character that the snapshot ended
    /// in the middle of. Empty when the snapshot fell between two sequences.
    let unfinishedBytes: [UInt8]

    /// Attaches to a session and restores its snapshot.
    init(socketPath: String, identifier: String, size: SessionSize = SessionSize(columns: 80, rows: 24)) throws {
        let connection = try MessageConnection.connect(to: SocketLocation(path: socketPath))
        let greeting = try withTimeLimit(30, on: connection) { try connection.greetSessionProcess() }
        if greeting.timedOut { throw ProtocolClientError.unexpected("The hello was not answered in time.") }
        try connection.send(ClientMessage.attach(identifier: UUID(uuidString: identifier)!, size: size))
        guard case .attached = try Self.receive(on: connection, within: 30) else {
            throw ProtocolClientError.unexpected("The first answer to attach was not attached.")
        }
        guard case .snapshot(let bytes) = try Self.receive(on: connection, within: 60) else {
            throw ProtocolClientError.unexpected("The second answer to attach was not a snapshot.")
        }
        let terminal = try TerminalSnapshot(bytes: Array(bytes)).restoreTerminal(scrollbackLimit: 10_000)
        self.connection = connection
        self.terminal = terminal
        unfinishedBytes = try UnfinishedSequence(of: terminal).bytes
    }

    /// One message, or `nil` when the connection closed. Throws when the time
    /// limit passes.
    static func receive(on connection: MessageConnection, within limit: TimeInterval) throws -> ServerMessage? {
        let (message, timedOut) = try withTimeLimit(limit, on: connection) { try connection.receive(ServerMessage.self) }
        if timedOut { throw ProtocolClientError.unexpected("No message arrived in \(limit) seconds.") }
        return message
    }

    /// Applies output to the restored terminal until the program exits.
    /// Returns the exit message.
    func followUntilExit() throws -> SessionExit {
        while let message = try Self.receive(on: connection, within: 60) {
            switch message {
            case .output(let bytes): terminal.write(bytes)
            case .exited(let exit): return exit
            default: continue
            }
        }
        throw ProtocolClientError.unexpected("The connection closed before the program exited.")
    }

    /// Applies output until the plain text satisfies the condition. Throws
    /// when the connection closes or the time limit passes first.
    func follow(until condition: (String) -> Bool) throws {
        while !condition(try text(withScrollback: false)) {
            guard let message = try Self.receive(on: connection, within: 60) else {
                throw ProtocolClientError.unexpected("The connection closed before the screen showed the text.")
            }
            if case .output(let bytes) = message { terminal.write(bytes) }
        }
    }

    func text(withScrollback: Bool) throws -> String {
        String(decoding: try terminal.formatted(.plainText, extent: withScrollback ? .withScrollback : .visible), as: UTF8.self)
    }

    func detach() {
        try? connection.send(ClientMessage.detach)
        connection.shutdown()
    }
}

private enum ProtocolClientError: Error {
    case unexpected(String)
}

/// Attaches again and again until a snapshot holds exactly the unfinished
/// bytes that the test is about, and returns that client. The program has
/// written them and waits, and the session process parses them a moment
/// later, so the first snapshot can still lack them. The wait is on the state
/// of the snapshot itself, not on time.
private func attachWhileTheSnapshotHolds(_ unfinished: [UInt8], process: RunningSessionProcess, identifier: String) async throws -> ProtocolClient {
    let deadline = ContinuousClock.now + .seconds(30)
    var lastSeen: [UInt8] = []
    while ContinuousClock.now < deadline {
        let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
        if client.unfinishedBytes == unfinished { return client }
        lastSeen = client.unfinishedBytes
        client.detach()
        try await Task.sleep(for: .milliseconds(25))
    }
    throw ProtocolClientError.unexpected("No snapshot held the unfinished bytes \(unfinished); the last held \(lastSeen).")
}

/// Receives one message, or `nil` when the connection closes or the time
/// limit passes. A test that waits too long fails instead of hanging.
private func receiveMessage(_ connection: MessageConnection, within limit: TimeInterval) throws -> ServerMessage? {
    let watchdog = DispatchWorkItem { connection.shutdown() }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    return try connection.receive(ServerMessage.self)
}

/// Starts a session with a size of its own, which `openrun new` cannot give.
private func createSession(in process: RunningSessionProcess, command: [String], size: SessionSize) throws -> UUID {
    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
    defer { connection.shutdown() }
    try connection.greetSessionProcess()
    try connection.send(ClientMessage.createSession(folder: process.directory.path, command: command, size: size, environment: ["PATH": "/usr/bin:/bin"]))
    guard case .sessionCreated(let summary) = try receiveMessage(connection, within: 30) else {
        throw ProtocolClientError.unexpected("The session was not created.")
    }
    return summary.identifier
}

/// What a slow client received after it attached.
private struct SlowAttachment: Sendable {
    var snapshotByteCount = 0
    var snapshotText = ""
    var outputAfterSnapshot = ""
    var problem: String?
}


extension SessionProcessIntegration {
    @Suite struct ReattachTests {
        @Test func outputWrittenWhileNoClientWasAttachedIsInTheSnapshot() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo written-while-detached; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "written-while-detached"))
                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { client.detach() }
                #expect(try client.text(withScrollback: false) == "written-while-detached")
            }
        }

        @Test func theSnapshotCarriesTheScreenAndTheScrollback() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 200; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "200"))
                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { client.detach() }

                let screen = try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines)
                let everything = try process.screenText(of: identifier, includeScrollback: true).trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(try client.text(withScrollback: false) == screen)
                #expect(try client.text(withScrollback: true) == everything)
                #expect(everything.hasPrefix("1\n2\n3\n"))
                #expect(everything.hasSuffix("199\n200"))
            }
        }

        @Test func aReattachedClientShowsTheSameScreenAndScrollback() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 100; echo \"$(printf '\\033[1;31m')bold red$(printf '\\033[0m')\"; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "bold red"))

                let first = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                let screenBefore = try first.text(withScrollback: false)
                let historyBefore = try first.text(withScrollback: true)
                let stylesBefore = try first.terminal.formatted(.virtualTerminalSequences)
                first.detach()

                let second = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { second.detach() }
                #expect(try second.text(withScrollback: false) == screenBefore)
                #expect(try second.text(withScrollback: true) == historyBefore)
                #expect(try second.terminal.formatted(.virtualTerminalSequences) == stylesBefore)
                // Detaching leaves the session running.
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test func aSnapshotTakenInsideAnEscapeSequenceContinuesCorrectly() async throws {
            try await RunningSessionProcess.run { process in
                // The program writes half of a color sequence, then waits for a
                // line of input. A client that attaches now gets a snapshot in the
                // middle of the sequence.
                let script = "stty -echo; printf '\\033[3'; read line; printf '1mRED\\033[0m\\n'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])

                // The snapshot must hold the unfinished bytes. Without them the
                // test would only watch ordinary output, and pass on any code.
                let client = try await attachWhileTheSnapshotHolds([0x1B, 0x5B, 0x33], process: process, identifier: identifier)
                defer { client.detach() }
                #expect(try client.text(withScrollback: false) == "")
                #expect(try process.runCommand(["send", identifier, "--enter", "go"]).status == 0)
                try client.follow { $0.contains("RED") }

                // Broken handling would print the rest of the sequence, "1mRED", as text.
                #expect(try client.text(withScrollback: false) == "RED")
                #expect(try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines) == "RED")
            }
        }

        @Test func aSnapshotTakenInsideACharacterContinuesCorrectly() async throws {
            try await RunningSessionProcess.run { process in
                // The first two of the three bytes of the euro sign.
                let script = "stty -echo; printf '\\342\\202'; read line; printf '\\254 euro\\n'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])

                let client = try await attachWhileTheSnapshotHolds([0xE2, 0x82], process: process, identifier: identifier)
                defer { client.detach() }
                #expect(try process.runCommand(["send", identifier, "--enter", "go"]).status == 0)
                try client.follow { $0.contains("euro") }

                #expect(try client.text(withScrollback: false) == "\u{20AC} euro")
                #expect(try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines) == "\u{20AC} euro")
            }
        }

        @Test(arguments: [50, 400, 1000, 1700])
        func attachingWhileOutputRunsLosesNothingAndRepeatsNothing(millisecondsBeforeAttach: Int) async throws {
            try await RunningSessionProcess.run { process in
                // About three seconds of steady output, so the attach lands in the middle.
                let script = "number=1; while [ $number -le 3000 ]; do echo line-$number; number=$((number+1)); if [ $((number % 20)) -eq 0 ]; then sleep 0.02; fi; done"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                try await Task.sleep(for: .milliseconds(millisecondsBeforeAttach))

                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                let exit = try client.followUntilExit()
                #expect(exit == .exited(status: 0))

                let lines = try client.text(withScrollback: true).split(separator: "\n").map(String.init)
                #expect(lines == (1...3000).map { "line-\($0)" })
            }
        }

        /// A client may fall 8 MiB of output behind. These two cases bracket
        /// the limit from both sides: a client that is 7 MiB behind keeps every
        /// byte, and one that is 9 MiB behind is dropped. A limit of 1 MiB or
        /// of 16 MiB fails one of them.
        struct FloodCase: Sendable, CustomTestStringConvertible {
            var byteCount: Int
            var isDropped: Bool
            var testDescription: String { "\(byteCount) bytes behind, dropped: \(isDropped)" }
        }

        @Test(arguments: [FloodCase(byteCount: 7 * 1024 * 1024, isDropped: false), FloodCase(byteCount: 9 * 1024 * 1024, isDropped: true)])
        func aClientThatNeverReadsIsDroppedOnlyPastTheLimitAndDoesNotBlockTheSession(flood: FloodCase) async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let againFile = process.directory.appendingPathComponent("again")
                // Zero bytes keep the terminal's own work small.
                let script = "stty -echo; echo ready; while [ ! -e '\(goFile.path)' ]; do sleep 0.05; done; "
                    + "dd if=/dev/zero bs=1048576 count=\(flood.byteCount / 1_048_576) 2>/dev/null; echo FLOOD-DONE; "
                    + "while [ ! -e '\(againFile.path)' ]; do sleep 0.05; done; echo after-reattach; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                let stuck = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { stuck.detach() }
                // The stuck client now never calls receive.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())

                // The session keeps working for others while the stuck client falls behind.
                #expect(await process.waitForScreen(of: identifier, containing: "FLOOD-DONE", timeout: .seconds(120)))
                #expect(try process.listedIdentifiers() == [identifier])

                // Now the client reads what it got, and the bytes are counted.
                var outputBytes = 0
                var text = Data()
                var sawExit = false
                var closed = false
                while !text.suffix(64).contains(Data("FLOOD-DONE".utf8)) {
                    guard let message = try ProtocolClient.receive(on: stuck.connection, within: 60) else {
                        closed = true
                        break
                    }
                    switch message {
                    case .output(let bytes):
                        outputBytes += bytes.count
                        text = Data((text + bytes).suffix(64))
                    case .exited:
                        sawExit = true
                    default:
                        break
                    }
                }
                print("slow-client: \(flood.byteCount) bytes of output, \(outputBytes) bytes received, connection closed: \(closed)")
                #expect(!sawExit)
                if flood.isDropped {
                    // The session dropped the client instead of keeping its
                    // backlog, so the end of the flood never arrived and the
                    // connection ended. Only what the socket held was delivered.
                    #expect(closed, "the client was not dropped after \(outputBytes) bytes")
                    #expect(outputBytes < flood.byteCount)
                } else {
                    // Every byte arrived: the zeros, a line end, and the words.
                    #expect(!closed, "the client was dropped after \(outputBytes) bytes")
                    #expect(outputBytes >= flood.byteCount)
                    #expect(outputBytes < flood.byteCount + 4096)
                }

                // A client that was dropped, or kept, can attach again and gets
                // a fresh snapshot and the output that follows it.
                stuck.detach()
                let again = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { again.detach() }
                #expect(try again.text(withScrollback: false).contains("FLOOD-DONE"))
                FileManager.default.createFile(atPath: againFile.path, contents: Data())
                try again.follow { $0.contains("after-reattach") }
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test func aClientThatAttachesWhileTheProgramIsOnTheAlternateScreenGetsTheAlternateScreen() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let script = "echo primary-line; printf '\\033[?1049h\\033[2J\\033[Halternate-line'; "
                    + "while [ ! -e '\(goFile.path)' ]; do sleep 0.05; done; printf '\\033[?1049l'; echo back-on-primary; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "alternate-line"))

                let client = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { client.detach() }
                #expect(client.terminal.isAlternateScreenActive)
                #expect(try client.text(withScrollback: false) == "alternate-line")

                // The program leaves the alternate screen, and the client that
                // followed the output leaves it with the program.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                try client.follow { $0.contains("back-on-primary") }
                #expect(!client.terminal.isAlternateScreenActive)
                #expect(try client.text(withScrollback: false).contains("primary-line"))
                #expect(!(try client.text(withScrollback: false).contains("alternate-line")))
            }
        }

        /// The session keeps 10,000 lines of scrollback. A program prints more
        /// than that, and the whole scrollback travels through the server to a
        /// client that attaches, and again to a client that attaches later.
        @Test func aFullScrollbackOfTenThousandLinesSurvivesAttachingAndReattaching() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let printed = 15_000
                let script = "awk 'BEGIN { for (number = 1; number <= \(printed); number++) printf \"row-%05d\\n\", number }'; echo FINISHED-PRINTING; "
                    + "while [ ! -e '\(goFile.path)' ]; do sleep 0.05; done; echo row-after-reattach; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "FINISHED-PRINTING", timeout: .seconds(60)))

                let everything = try process.screenText(of: identifier, includeScrollback: true)
                let rowNumbers = everything.split(separator: "\n").compactMap { line -> Int? in
                    line.hasPrefix("row-") ? Int(line.dropFirst(4)) : nil
                }
                print("full-scrollback: the server kept \(rowNumbers.count) rows, from \(rowNumbers.first ?? -1) to \(rowNumbers.last ?? -1)")
                // The scrollback is full: the oldest rows are gone, the rows that
                // stay are the newest, in order, each once and without a gap.
                // libghostty-vt prunes whole pages, so the count of lines is
                // near the limit of 10,000 and not exactly at it.
                #expect(rowNumbers.last == printed)
                #expect(rowNumbers.count >= 9_000, "the server kept only \(rowNumbers.count) rows")
                #expect(rowNumbers.count <= 11_000, "the server kept \(rowNumbers.count) rows")
                #expect(rowNumbers == Array((printed - rowNumbers.count + 1)...printed))

                let first = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                #expect((9_000...11_000).contains(first.terminal.scrollbackLineCount), "the client got \(first.terminal.scrollbackLineCount) lines of scrollback")
                let firstText = try first.text(withScrollback: true)
                #expect(firstText.trimmingCharacters(in: .whitespacesAndNewlines) == everything.trimmingCharacters(in: .whitespacesAndNewlines))
                first.detach()

                // Output continues after the reattach, and the scrollback stays
                // full and consistent: the new row is the newest.
                let second = try ProtocolClient(socketPath: process.socketPath, identifier: identifier)
                defer { second.detach() }
                #expect(try second.text(withScrollback: true) == firstText)
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                try second.follow { $0.contains("row-after-reattach") }
                let afterwards = try second.text(withScrollback: true).split(separator: "\n").map(String.init)
                #expect(afterwards.last == "row-after-reattach")
                #expect(afterwards.contains("row-\(String(format: "%05d", printed))"))
                #expect(!afterwards.contains("row-00001"))
                #expect((9_000...11_000).contains(second.terminal.scrollbackLineCount))
            }
        }

        /// 8,000 lines of 239 characters, each character in its own color, then
        /// a line every 20 milliseconds.
        private static let styledLinesProgram = #"""
            $| = 1;
            for my $line (1 .. 8000) {
                my $text = '';
                for my $column (1 .. 239) {
                    $text .= sprintf("\e[38;5;%dm%c", ($column * 7 + $line) % 256, 97 + ($column + $line) % 26);
                }
                print $text, "\e[0m\n";
            }
            print "styled-done\n";
            while (1) {
                print "tick\n";
                select(undef, undef, undef, 0.02);
            }
            """#

        /// A snapshot larger than the 8 MiB that a client may fall
        /// behind made the next output frame end the connection mid-snapshot.
        @Test func aStyledSnapshotLargerThanTheOutputLimitArrivesWholeWhileTheProgramPrints() async throws {
            try await RunningSessionProcess.run { process in
                let program = process.directory.appendingPathComponent("styled-lines")
                try Self.styledLinesProgram.write(to: program, atomically: true, encoding: .utf8)
                let size = SessionSize(columns: 240, rows: 50)
                let identifier = try createSession(in: process, command: ["/usr/bin/perl", program.path], size: size)
                #expect(await process.waitForScreen(of: SessionSummary.text(for: identifier), containing: "tick", timeout: .seconds(120)))

                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()
                try connection.send(ClientMessage.attach(identifier: identifier, size: size))
                // The client reads nothing for a second, so output waits behind the snapshot.
                try await Task.sleep(for: .seconds(1))

                let attachment = await BlockingWork.onNewThread { () -> SlowAttachment in
                    var attachment = SlowAttachment()
                    do {
                        guard case .attached = try receiveMessage(connection, within: 30) else {
                            attachment.problem = "The first answer to attach was not attached."
                            return attachment
                        }
                        guard case .snapshot(let bytes) = try receiveMessage(connection, within: 60) else {
                            attachment.problem = "The second answer to attach was not a snapshot."
                            return attachment
                        }
                        attachment.snapshotByteCount = bytes.count
                        let terminal = try TerminalSnapshot(bytes: Array(bytes)).restoreTerminal(scrollbackLimit: 10_000)
                        attachment.snapshotText = String(decoding: try terminal.formatted(.plainText, extent: .withScrollback), as: UTF8.self)
                        while !attachment.outputAfterSnapshot.contains("tick") {
                            guard let message = try receiveMessage(connection, within: 30) else {
                                attachment.problem = "The connection closed after the snapshot."
                                return attachment
                            }
                            if case .output(let output) = message { attachment.outputAfterSnapshot += String(decoding: output, as: UTF8.self) }
                        }
                    } catch {
                        attachment.problem = "\(error)"
                    }
                    return attachment
                }
                print("large-snapshot: \(attachment.snapshotByteCount) bytes")
                #expect(attachment.problem == nil, "\(attachment.problem ?? "")")
                #expect(attachment.snapshotByteCount > 8 * 1024 * 1024, "the snapshot has \(attachment.snapshotByteCount) bytes")
                #expect(attachment.snapshotText.contains("styled-done"))
                #expect(attachment.outputAfterSnapshot.contains("tick"))
            }
        }

        /// Rows of 500 wide characters in many colors fill 1000 columns. A
        /// snapshot of the whole scrollback is larger than one frame.
        private static let wideColorfulProgram = #"""
            binmode(STDOUT, ':utf8');
            for my $line (1 .. 10200) {
                print map({ sprintf("\e[38;5;%dm", ($_ * 5 + $line) % 256) . (chr(0x4E00 + ($line + $_) % 9000) x 10) } 0 .. 49), "\e[0m\n";
            }
            $| = 1;
            print "wide-done\n";
            select(undef, undef, undef, 0.05) until -e $ARGV[0];
            print "after-attach\n";
            sleep 600;
            """#

        /// A snapshot larger than one frame ended the attach
        /// after `attached`, with no snapshot and no failure.
        @Test func aSnapshotLargerThanOneFrameLosesOldScrollbackAndKeepsTheScreen() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                let program = process.directory.appendingPathComponent("wide-colorful")
                try Self.wideColorfulProgram.write(to: program, atomically: true, encoding: .utf8)
                let size = SessionSize(columns: 1000, rows: 50)
                let identifier = try createSession(in: process, command: ["/usr/bin/perl", program.path, goFile.path], size: size)
                let identifierText = SessionSummary.text(for: identifier)
                #expect(await process.waitForScreen(of: identifierText, containing: "wide-done", timeout: .seconds(120)))
                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()

                // 10,000 rows pull the scrollback onto the screen, and the screen alone does not fit.
                try connection.send(ClientMessage.attach(identifier: identifier, size: SessionSize(columns: 1000, rows: 10_000)))
                let refusal = try receiveMessage(connection, within: 60)
                guard case .failure(let failure) = refusal, failure.message.contains("does not fit in one frame") else {
                    Issue.record("The attach at 10,000 rows was answered with \(String(describing: refusal)).")
                    return
                }
                // The client is not attached, and the session keeps its size.
                try connection.send(ClientMessage.listSessions)
                guard case .sessionList(let summaries) = try receiveMessage(connection, within: 30) else {
                    Issue.record("The list did not follow the refusal.")
                    return
                }
                #expect(summaries.first?.size == size)

                try connection.send(ClientMessage.attach(identifier: identifier, size: size))
                guard case .attached = try receiveMessage(connection, within: 60),
                      case .snapshot(let bytes) = try receiveMessage(connection, within: 60) else {
                    Issue.record("The attach was not answered with attached and a snapshot.")
                    return
                }
                #expect(bytes.count <= MessageFrame.maximumPayloadLength)
                #expect(bytes.count > MessageFrame.maximumPayloadLength - 4 * 1_048_576, "the snapshot has \(bytes.count) bytes")
                let terminal = try TerminalSnapshot(bytes: Array(bytes)).restoreTerminal(scrollbackLimit: 10_000)
                func text(_ extent: ScreenExtent) throws -> [UInt8] { try terminal.formatted(.plainText, extent: extent) }
                func showsWhatReadShows() throws -> Bool {
                    try String(decoding: text(.visible), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        == process.screenText(of: identifierText).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                #expect(try showsWhatReadShows())
                // The snapshot holds the newest lines of the scrollback. `openrun read` adds a line end.
                let everything = Array(try process.screenText(of: identifierText, includeScrollback: true).utf8.dropLast())
                let kept = try text(.withScrollback)
                print("wide-snapshot: \(bytes.count) bytes, \(kept.count) of \(everything.count) bytes of text")
                #expect(kept.count < everything.count && everything.dropLast(kept.count).last == 0x0A)
                #expect(everything.suffix(kept.count).elementsEqual(kept))

                // The output after the snapshot continues the screen that `openrun read` shows.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                while !String(decoding: try text(.visible), as: UTF8.self).contains("after-attach") {
                    guard case .output(let output) = try receiveMessage(connection, within: 60) else { break }
                    terminal.write(output)
                }
                #expect(try showsWhatReadShows())
            }
        }

        /// An answer to readScreen counted toward the limit for output
        /// that waits, so a large answer ended the connection.
        @Test func aScreenAnswerIsNotCountedAgainstTheLimitForOutputThatWaits() async throws {
            try await RunningSessionProcess.run { process in
                let goFile = process.directory.appendingPathComponent("go")
                // About 1.9 MB of text in the scrollback, then 7 MiB of output
                // that the client does not read.
                let script = "awk 'BEGIN { for (number = 1; number <= 12000; number++) printf \"row-%05d-%0180d\\n\", number, 0 }'; echo ready; "
                    + "while [ ! -e '\(goFile.path)' ]; do sleep 0.05; done; dd if=/dev/zero bs=1048576 count=7 2>/dev/null; echo zeros-done; sleep 600"
                let size = SessionSize(columns: 200, rows: 50)
                let identifier = try createSession(in: process, command: ["/bin/sh", "-c", script], size: size)
                let identifierText = SessionSummary.text(for: identifier)
                #expect(await process.waitForScreen(of: identifierText, containing: "ready", timeout: .seconds(60)))

                let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { connection.shutdown() }
                try connection.greetSessionProcess()
                try connection.send(ClientMessage.attach(identifier: identifier, size: size))
                guard case .attached = try receiveMessage(connection, within: 30),
                      case .snapshot = try receiveMessage(connection, within: 30) else {
                    Issue.record("The attach was not answered.")
                    return
                }

                // The client stops reading. 7 MiB of output wait for it, below the limit.
                FileManager.default.createFile(atPath: goFile.path, contents: Data())
                #expect(await process.waitForScreen(of: identifierText, containing: "zeros-done", timeout: .seconds(30)))
                try connection.send(ClientMessage.readScreen(identifier: identifier, includeScrollback: true))
                try await Task.sleep(for: .milliseconds(300))

                let (outputByteCount, screen, problem) = await BlockingWork.onNewThread { () -> (Int, String?, String?) in
                    var outputByteCount = 0
                    do {
                        while let message = try receiveMessage(connection, within: 30) {
                            switch message {
                            case .output(let bytes): outputByteCount += bytes.count
                            case .screen(let text): return (outputByteCount, text, nil)
                            default: continue
                            }
                        }
                        return (outputByteCount, nil, "The connection closed before the screen arrived.")
                    } catch {
                        return (outputByteCount, nil, "\(error)")
                    }
                }
                print("screen-answer: \(outputByteCount) output bytes, then a screen of \(screen?.utf8.count ?? 0) bytes")
                #expect(problem == nil, "\(problem ?? "")")
                #expect(outputByteCount >= 7 * 1024 * 1024)
                #expect((screen?.utf8.count ?? 0) > 1024 * 1024)
                #expect(screen?.contains("row-12000-") == true)
            }
        }
    }
}
