import Darwin
import Dispatch
import Foundation
import SessionProtocol
import TerminalEmulation

struct AttachCommand {
    var identifier: String


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

    }

    /// The closing sequences, and where in them the alternate screen and
    /// the title are done with.
    private struct ClosingSequences {
        var bytes: [UInt8]
        var alternateScreenEnd: Int?
        var titleEnd: Int?
    }

}
