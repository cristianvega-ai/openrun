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

}
