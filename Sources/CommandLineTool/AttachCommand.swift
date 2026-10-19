import Darwin
import Dispatch
import Foundation
import SessionProtocol
import TerminalEmulation

struct AttachCommand {
    var identifier: String

    // Sent when attaching ends or is suspended, to undo what the session's
    // program switched on in this terminal. See `LocalScreen.closingSequences`.
    private static let endOfOpenSequence = "\u{18}\u{1B}\\"
    // Synchronized output holds back every later change of the screen until
    // it ends, so it goes off before anything else.
    private static let synchronizedOutputOff = "\u{1B}[?2026l"
    private static let leaveAlternateScreen = "\u{1B}[?1049l"
    // Resetting the scroll region and origin mode moves the cursor, so the
    // cursor is saved and restored around them. A saved cursor also keeps the
    // origin mode, so when the program set it, it is reset after the restore,
    // and the cursor goes back to where it was by position. On the alternate
    // screen it goes before the screen is left, because that screen forgets
    // its cursor, and leaving it restores the cursor of the main screen.
    private static let originModeOff = "\u{1B}[?6l"
    private static let saveCursorAndResetScrollRegion = "\u{1B}7\u{1B}[r"
    private static let restoreCursor = "\u{1B}8"
    private static let resetSequences = "\u{1B}]104\u{1B}\\\u{1B}]110\u{1B}\\\u{1B}]111\u{1B}\\\u{1B}]112\u{1B}\\\u{1B}[0m"
        + "\u{1B}]8;;\u{1B}\\"
        + "\u{1B}(B\u{1B})B\u{0F}\u{1B}[4l\u{1B}[?7h\u{1B}[?5l\u{1B}[?25h\u{1B}[0 q"
        + "\u{1B}[2l\u{1B}[20l\u{1B}[?67l\u{1B}[?69l"
        + "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
        + "\u{1B}[?1004l\u{1B}[?2004l\u{1B}[?2031l\u{1B}[?2033l\u{1B}[?2048l"
        + "\u{1B}[?1l\u{1B}>\u{1B}[<99u\u{1B}[>4;0m"

    private static let detached = TerminalWriter.Ending(exitCode: 0, message: "detached")

    func run(location: SocketLocation) throws -> Int32 {
        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
            throw CommandLineToolError.failure("attach needs a terminal. Use send and read in scripts.")
        }
        let client = try SessionClient(location: location)
        let session = try client.session(matching: identifier)
        let size = RawTerminalMode.windowSize(of: STDOUT_FILENO) ?? session.size

        try client.connection.send(ClientMessage.attach(identifier: session.identifier, size: size, relaysRawOutput: true))
        let snapshot = try receiveSnapshot(from: client)
        // Made before the terminal changes, so a snapshot that cannot be
        // restored ends attaching with an error, not with a blank picture.
        let screen = try LocalScreen(snapshot: snapshot)

        let connection = client.connection
        let writer = try TerminalWriter()
        defer { writer.stopWriting() }
        let resizes = DispatchQueue(label: "attach.resize")
        // Signals are handled before raw mode starts, so none can leave the
        // terminal raw.
        let signals = AttachSignals { event in
            switch event {
            case .stop(let signal):
                writer.requestEnd(TerminalWriter.Ending(exitCode: 128 + signal), afterOutput: false)
            case .suspend:
                writer.requestSuspension(true)
            case .resume:
                writer.requestSuspension(false)
            case .resize:
                resizes.async { Self.sendWindowSize(on: connection) }
            }
        }
        defer { signals.cancel() }
        if let ending = writer.endingBeforeStart {
            return ending.exitCode
        }

        let mode = try RawTerminalMode(descriptor: STDIN_FILENO)
        let keys = KeySender(connection: connection)
        keys.start { writer.requestEnd(Self.detached, afterOutput: false) }
        let receiver = Thread {
            Self.receiveOutput(from: connection, into: writer, keys: keys)
        }
        receiver.name = "attach.receiver"
        receiver.start()
        // The window may have changed between the attach request and the
        // signal handler, and that change would be lost.
        resizes.async { Self.sendWindowSize(on: connection) }

        let ending = relay(writer: writer, screen: screen, mode: mode, keys: keys, resizes: resizes, connection: connection)

        writer.close()
        keys.stop()
        Self.writeClosing(screen, with: writer, restoring: mode)
        writer.stopWriting()
        if let message = ending.message {
            // The message can include text from the session process, such as
            // the reason of a lost connection.
            TerminalWriter.writeLastMessage("\n[\(PrintableText.escaping(message))]\n")
        }
        return ending.exitCode
    }

    // MARK: - Attaching

    private func receiveSnapshot(from client: SessionClient) throws -> TerminalSnapshot {
        for _ in 0..<2 {
            do {
                switch try client.connection.receive(ServerMessage.self) {
                case .attached:
                    continue
                case .snapshot(let bytes):
                    return TerminalSnapshot(bytes: Array(bytes))
                case .failure(let failure):
                    throw CommandLineToolError.failure(failure.message)
                default:
                    throw CommandLineToolError.failure("The session process answered the attach request in an unexpected way.")
                }
            } catch let error as SessionProtocolError {
                throw CommandLineToolError.failure("\(error)")
            }
        }
        throw CommandLineToolError.failure("The session process sent no snapshot.")
    }

    /// The screen of the session, kept in this process. It draws the
    /// picture, at the start and after a suspension. Then it follows the
    /// bytes that reached the terminal, and no others, so the end of the
    /// attach knows whether the terminal is on the alternate screen.
    /// It installs no reply handler. This client says in its attach message that
    /// it relays raw output, so the terminal window answers the queries and the
    /// session process stays silent. A handler here would answer a second time.
    /// Only the main thread uses it.
    private final class LocalScreen {
        private static let enterAlternateScreen = Array("\u{1B}[?1049h".utf8)
        // Saves the title of the window on a stack, so the closing sequences
        // can put it back: a program may have changed it.
        private static let pushTitle = Array("\u{1B}[22;0t".utf8)
        private static let popTitle = "\u{1B}[23;0t"

        private let terminal: Terminal
        let firstPicture: [UInt8]
        /// Whether the terminal window is on the alternate screen, as far as
        /// the bytes that reached it tell.
        private var windowIsOnAlternateScreen = false
        /// Whether the title that the window had is on its stack.
        private var windowHoldsTheTitle = false

        init(snapshot: TerminalSnapshot) throws {
            do {
                terminal = try snapshot.restoreTerminal(scrollbackLimit: 10_000)
                firstPicture = try Self.picture(of: terminal)
            } catch {
                throw CommandLineToolError.failure("The snapshot of the session cannot be restored: \(error).")
            }
        }

        /// Saves the title, clears the terminal and draws the visible screen.
        func picture() throws -> [UInt8] {
            try Self.picture(of: terminal)
        }

        private static func picture(of terminal: Terminal) throws -> [UInt8] {
            var picture = pushTitle
            if terminal.isAlternateScreenActive { picture += enterAlternateScreen }
            picture += Array("\u{1B}[H\u{1B}[2J".utf8)
            picture += try terminal.formatted(.virtualTerminalSequences, extent: .visible)
            // The snapshot can fall inside an escape sequence or a UTF-8 character.
            // The picture holds only what is finished, so the start goes after it,
            // and the output that follows finishes it here as well.
            picture += try UnfinishedSequence(of: terminal).bytes
            return picture
        }

        /// Notes how much of a picture reached the terminal.
        func pictureReached(_ count: Int, of picture: [UInt8]) {
            let titleLength = Self.pushTitle.count
            if count >= titleLength { windowHoldsTheTitle = true }
            if picture.dropFirst(titleLength).starts(with: Self.enterAlternateScreen)
                && count >= titleLength + Self.enterAlternateScreen.count {
                windowIsOnAlternateScreen = true
            }
        }

        /// Follows output that reached the terminal.
        func follow(_ bytes: ArraySlice<UInt8>) {
            terminal.write(bytes)
            windowIsOnAlternateScreen = terminal.isAlternateScreenActive
        }

        /// Whether the program set origin mode. The terminal has no question
        /// for a mode, but its picture names every mode that differs from the
        /// default.
        private var originModeIsOn: Bool {
            guard let picture = try? Self.picture(of: terminal) else { return false }
            return picture.indices.contains { start in
                picture[start...].starts(with: Array("\u{1B}[?6h".utf8))
            }
        }

        /// The sequences that undo what the program switched on. They leave
        /// the alternate screen, and `closingReached` says when the window
        /// counts as on the main screen.
        ///
        /// CAN ends any escape sequence, and ST any string, such as an operating
        /// system command, that the program left open; otherwise the terminal
        /// could take what follows as part of it. Synchronized output goes off
        /// next, because it would hold back the rest. The alternate screen goes
        /// next, because some settings belong to each screen. Resetting the
        /// scroll region and origin mode moves the cursor, so the cursor is
        /// saved and restored around them. Then come the colors (the palette, which the first
        /// picture sets, and OSC 10 to 12), styles, a hyperlink that is still
        /// open, character sets, insert mode, reverse video, line wrap, the
        /// cursor and its shape, the modes that lock the keyboard or change a
        /// key (2, 20, 67), the margins at the sides (69), mouse reports and
        /// their encodings, focus, color scheme and size reports, bracketed
        /// paste, application keys, and the extended keyboard modes. When the
        /// program set origin mode, the reset comes after the restore of the
        /// cursor, with the cursor moved back. The title is put back last, and
        /// only when this screen saved it.
        func closingSequences() -> ClosingSequences {
            let onAlternateScreen = windowIsOnAlternateScreen
            let originModeIsOn = originModeIsOn
            var closing = AttachCommand.endOfOpenSequence + AttachCommand.synchronizedOutputOff
            var alternateScreenEnd: Int?
            if onAlternateScreen {
                closing += (originModeIsOn ? AttachCommand.originModeOff : "") + AttachCommand.leaveAlternateScreen
                alternateScreenEnd = closing.utf8.count
            }
            closing += AttachCommand.saveCursorAndResetScrollRegion
                + (originModeIsOn ? "" : AttachCommand.originModeOff)
                + AttachCommand.restoreCursor
                + AttachCommand.resetSequences
            if originModeIsOn && !onAlternateScreen {
                let cursor = terminal.cursorPosition
                closing += AttachCommand.originModeOff + "\u{1B}[\(Int(cursor.row) + 1);\(Int(cursor.column) + 1)H"
            }
            if windowHoldsTheTitle { closing += Self.popTitle }
            return ClosingSequences(
                bytes: Array(closing.utf8),
                alternateScreenEnd: alternateScreenEnd,
                titleEnd: windowHoldsTheTitle ? closing.utf8.count : nil
            )
        }

        /// Notes how much of the closing sequences reached the terminal. A
        /// state counts as ended only when the bytes that end it went out,
        /// so a closing that timed out on a frozen terminal is made again
        /// whole. The title pop is the last part, and it changes the stack
        /// each time, so it is never sent twice.
        func closingReached(_ count: Int, of closing: ClosingSequences) {
            if let end = closing.alternateScreenEnd, count >= end { windowIsOnAlternateScreen = false }
            if let end = closing.titleEnd, count >= end { windowHoldsTheTitle = false }
        }
    }

    /// The closing sequences, and where in them the alternate screen and
    /// the title are done with.
    private struct ClosingSequences {
        var bytes: [UInt8]
        var alternateScreenEnd: Int?
        var titleEnd: Int?
    }

    // MARK: - Relaying

    private static func writeClosing(_ screen: LocalScreen, with writer: TerminalWriter, restoring mode: RawTerminalMode) {
        let closing = screen.closingSequences()
        screen.closingReached(writer.writeClosing(closing.bytes, restoring: mode), of: closing)
    }

    /// Writes the picture and the output until a request ends attaching, and
    /// returns how it ended.
    private func relay(
        writer: TerminalWriter,
        screen: LocalScreen,
        mode: RawTerminalMode,
        keys: KeySender,
        resizes: DispatchQueue,
        connection: MessageConnection
    ) -> TerminalWriter.Ending {
        // The picture goes through the writer too, so a signal can end the
        // attach while the picture waits for the terminal.
        var pictureToDraw: [UInt8]? = screen.firstPicture
        var output: [UInt8] = []
        var isSuspended = false
        while true {
            let hasWork = !isSuspended && (pictureToDraw != nil || !output.isEmpty)
            if let request = writer.nextRequest(isSuspended: isSuspended, waiting: !hasWork) {
                switch request {
                case .end(let ending):
                    return ending
                case .write(let bytes):
                    output += bytes
                case .suspend:
                    // Until the resume sets raw mode again, a key belongs to
                    // the shell, which gets the terminal back.
                    keys.pause()
                    Self.writeClosing(screen, with: writer, restoring: mode)
                    isSuspended = true
                    if writer.mayStopProcess {
                        // SIGSTOP, not SIGTSTP: a SIGTSTP of our own would reach
                        // the signal handler again after the continue.
                        kill(getpid(), SIGSTOP)
                    }
                case .resume:
                    guard (try? mode.enter()) != nil, let picture = try? screen.picture() else {
                        return TerminalWriter.Ending(exitCode: 1, message: "the terminal cannot be set up again after the suspension")
                    }
                    keys.resume()
                    pictureToDraw = picture
                    isSuspended = false
                    resizes.async { Self.sendWindowSize(on: connection) }
                }
                continue
            }
            let result: TerminalWriter.WriteResult
            if let picture = pictureToDraw {
                result = writer.write(picture)
                screen.pictureReached(result.writtenCount ?? picture.count, of: picture)
                // An interrupted picture is drawn again whole after a suspension.
                if result == .written { pictureToDraw = nil }
            } else {
                result = writer.write(output)
                let written = result.writtenCount ?? output.count
                screen.follow(output[..<written])
                output.removeFirst(written)
            }
            if case .failed(_, let reason) = result {
                return TerminalWriter.Ending(exitCode: 1, message: "writing to the terminal failed: \(reason)")
            }
        }
    }

    /// Receives output and the end of the session, and hands both to the
    /// writer in order.
    private static func receiveOutput(from connection: MessageConnection, into writer: TerminalWriter, keys: KeySender) {
        while true {
            let message: ServerMessage?
            do {
                message = try connection.receive(ServerMessage.self)
            } catch {
                // Detaching shuts the socket down while this loop may be in the
                // middle of reading a frame. That read then fails, and the failure
                // is the detach itself, not a lost connection.
                let ending = keys.isDetaching ? detached : TerminalWriter.Ending(exitCode: 1, message: "connection lost: \(error)")
                writer.requestEnd(ending, afterOutput: true)
                return
            }
            switch message {
            case .output(let bytes):
                guard writer.enqueue(output: Array(bytes)) else { return }
            case .exited(let exit):
                writer.requestEnd(TerminalWriter.Ending(exitCode: exitCode(for: exit), message: "program \(exit)"), afterOutput: true)
                return
            case nil:
                let ending = keys.isDetaching ? detached : TerminalWriter.Ending(exitCode: 1, message: "the session process closed the connection")
                writer.requestEnd(ending, afterOutput: true)
                return
            default:
                continue
            }
        }
    }

    /// The exit code for how the program ended: its status, or 128 plus the
    /// signal, as a shell reports it. A process exit code holds 0 to 255, and
    /// the kernel would keep only the low byte, so 300 would become 44. The
    /// session process is another program, so its numbers are clamped.
    static func exitCode(for exit: SessionExit) -> Int32 {
        let code: Int64 = switch exit {
        case .exited(let status): Int64(status)
        case .signaled(let signal): 128 + Int64(signal)
        }
        return Int32(Swift.min(Swift.max(code, 0), 255))
    }

    private static func sendWindowSize(on connection: MessageConnection) {
        if let size = RawTerminalMode.windowSize(of: STDOUT_FILENO) {
            try? connection.send(ClientMessage.resize(size))
        }
    }
}
