import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

@testable import CommandLineTool
extension CommandLineToolIntegration {
    @Suite struct AttachRestoreTests {

        /// Keys typed before attaching and while leaving stay for the program
        /// that reads the terminal next.
        @Test func rawModeKeepsTheKeysTypedAheadWhenItStartsAndWhenItEnds() throws {
            let spare = try TerminalControl.SpareTerminal()
            let descriptor = open(spare.path, O_RDWR | O_NOCTTY)
            try #require(descriptor >= 0)
            defer { close(descriptor) }
            // Without echo, no output waits for a window that this test does not have.
            var settings = termios()
            tcgetattr(descriptor, &settings)
            settings.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(descriptor, TCSANOW, &settings)

            spare.type(Array("before".utf8))
            let mode = try RawTerminalMode(descriptor: descriptor)
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 6)

            spare.type(Array("after\n".utf8))
            mode.restore()
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 12)
        }
    }
}

/// The number of keys that a stand-in session has received.
private final class ReceivedKeyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var total: Int { lock.withLock { count } }

    func add(_ keys: Int) {
        lock.withLock { count += keys }
    }
}
