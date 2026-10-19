import Darwin
import Foundation
import TerminalEmulation

public enum TerminalControl {
    /// `FIONREAD`, `_IOR('f', 127, int)`. Swift cannot import the macro.
    private static let waitingInputRequest = UInt(0x4004_667F)

    /// The path of the controlling terminal of a process, such as
    /// `/dev/ttys004`, or `nil` when it has none.
    public static func terminalPath(ofProcess processIdentifier: pid_t) -> String? {
        guard let details = processDetails(processIdentifier) else { return nil }
        // A process without a terminal has the device number -1.
        guard details.e_tdev != UInt32.max, let name = devname(dev_t(bitPattern: details.e_tdev), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// Whether a process is stopped, as by SIGSTOP or SIGTSTP.
    public static func isStopped(process processIdentifier: pid_t) -> Bool {
        processDetails(processIdentifier)?.pbi_status == UInt32(SSTOP)
    }

    /// Whether a process still exists. Its parent reaps it soon after it ends.
    public static func exists(process processIdentifier: pid_t) -> Bool {
        kill(processIdentifier, 0) == 0 || errno == EPERM
    }

    /// The memory that a process uses, as Activity Monitor counts it.
    public static func memoryFootprint(of processIdentifier: pid_t) -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }

    /// The bytes that wait in a terminal for a program to read them.
    public static func waitingInput(onTerminal path: String) -> Int? {
        queueLength(onTerminal: path, request: waitingInputRequest)
    }

    private static func processDetails(_ processIdentifier: pid_t) -> proc_bsdinfo? {
        var details = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &details, size) == size else { return nil }
        return details
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
