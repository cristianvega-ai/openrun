import Darwin
import Foundation
import TerminalEmulation

public enum TerminalControl {
    /// `FIONREAD`, `_IOR('f', 127, int)`. Swift cannot import the macro.
    private static let waitingInputRequest = UInt(0x4004_667F)


    /// The bytes that wait in a terminal for a program to read them.
    public static func waitingInput(onTerminal path: String) -> Int? {
        queueLength(onTerminal: path, request: waitingInputRequest)
    }

    private static func queueLength(onTerminal path: String, request: UInt) -> Int? {
        // O_NOCTTY keeps the test from adopting the terminal.
        let descriptor = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var count: Int32 = 0
        guard ioctl(descriptor, request, &count) == 0 else { return nil }
        return Int(count)
    }

    /// A second terminal with no window. A test points the output of
    /// `openrun attach` at it and then takes the window away, so every
    /// later write to it fails.
    public final class SpareTerminal: @unchecked Sendable {
        /// The path that a program opens to write to the terminal.
        public let path: String
        private let lock = NSLock()
        private var controllingDescriptor: Int32

        public init() throws {
            let descriptor = posix_openpt(O_RDWR | O_NOCTTY)
            var name = [CChar](repeating: 0, count: 128)
            guard descriptor >= 0, grantpt(descriptor) == 0, unlockpt(descriptor) == 0,
                  ptsname_r(descriptor, &name, name.count) == 0 else {
                let reason = String(cString: strerror(errno))
                if descriptor >= 0 { close(descriptor) }
                throw HarnessError.commandFailed(description: "No spare terminal: \(reason)")
            }
            controllingDescriptor = descriptor
            path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }

        deinit { closeWindow() }

        /// Types bytes, as keys, into the terminal.
        public func type(_ bytes: [UInt8]) {
            lock.withLock {
                guard controllingDescriptor >= 0 else { return }
                _ = bytes.withUnsafeBytes { write(controllingDescriptor, $0.baseAddress, $0.count) }
            }
        }

        /// Takes the window away. Writes to the terminal then fail with EIO.
        public func closeWindow() {
            lock.withLock {
                if controllingDescriptor >= 0 { close(controllingDescriptor) }
                controllingDescriptor = -1
            }
        }
    }
}
