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

        /// A key that arrives after `stop` is for the next reader of the terminal,
        /// the shell. The keyboard thread may be inside its wait for keys when
        /// `stop` lands, and it used to read the key and drop it.
        @Test func keysTypedAfterTheKeyboardThreadWasStoppedStayInTheTerminal() async throws {
            let spare = try TerminalControl.SpareTerminal()
            let descriptor = open(spare.path, O_RDWR | O_NOCTTY)
            try #require(descriptor >= 0)
            defer { close(descriptor) }
            var settings = termios()
            tcgetattr(descriptor, &settings)
            settings.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(descriptor, TCSANOW, &settings)
            let mode = try RawTerminalMode(descriptor: descriptor)
            defer { mode.restore() }

            let (clientSide, sessionSide) = try MessageConnection.makePair()
            let counter = ReceivedKeyCounter()
            let receiver = Thread {
                while let message = try? sessionSide.receive(ClientMessage.self) {
                    if case .input(let keys) = message { counter.add(keys.count) }
                }
            }
            receiver.start()
            let sender = KeySender(connection: clientSide, inputDescriptor: descriptor)
            sender.start(onDetach: {})

            // Keys typed while the thread runs reach the session.
            spare.type(Array("before-stop".utf8))
            #expect(await eventually { counter.total == 11 })

            sender.stop()
            let sentBeforeStop = counter.total
            // The thread is inside its wait for keys now. These keys come later.
            for _ in 0..<5 {
                spare.type(Array("after-stop".utf8))
                try await Task.sleep(for: .milliseconds(30))
            }
            try await Task.sleep(for: .milliseconds(300))

            #expect(counter.total == sentBeforeStop, "the session got keys that were typed after the stop")
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 50)
            clientSide.shutdown()
            sessionSide.shutdown()
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
