import Darwin

/// The program that reads the keys of a terminal: the leader of its
/// foreground process group.
///
/// On macOS, `tcgetpgrp` on the master side reports the group of the session
/// leader, also while a command runs in the foreground. The leader's own
/// process information holds the true foreground group of its terminal.
public struct ForegroundProgram: Equatable, Sendable {
    /// The name of the program, such as `zsh` at a prompt or `vim` while it runs.
    public let name: String
    /// The command line of the program, from its first argument (`argv[0]`).
    public let arguments: [String]

    public init(name: String, arguments: [String]) {
        self.name = name
        self.arguments = arguments
    }

    /// The foreground program of the terminal that `sessionLeader` controls.
    /// Nil when the system does not say, as when the group's leader has ended.
    static func find(inSessionOf sessionLeader: pid_t) -> ForegroundProgram? {
        findGroup(inSessionOf: sessionLeader)?.program
    }

    /// The foreground program, and its process, which leads its group.
    static func findGroup(inSessionOf sessionLeader: pid_t) -> (group: pid_t, program: ForegroundProgram)? {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(sessionLeader, PROC_PIDTBSDINFO, 0, &information, size) == size else { return nil }
        let group = pid_t(bitPattern: information.e_tpgid)
        // A process group identifier is the identifier of the process that
        // made the group, and no new process gets it while the group lives.
        guard group > 0, getpgid(group) == group, getsid(group) == sessionLeader else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        guard proc_name(group, &buffer, UInt32(buffer.count)) > 0, let arguments = arguments(of: group) else { return nil }
        return (group, ForegroundProgram(name: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), arguments: arguments))
    }

    /// The current folder of a process, or nil when the system does not say.
    static func currentFolder(of process: pid_t) -> String? {
        var information = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(process, PROC_PIDVNODEPATHINFO, 0, &information, size) == size else { return nil }
        let path = withUnsafeBytes(of: &information.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    /// Reads the arguments from `KERN_PROCARGS2`: the count, the path of the
    /// executable, padding, and then the arguments, each ended by a zero.
    private static func arguments(of process: pid_t) -> [String]? {
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, process]
        var length = 0
        guard sysctl(&name, 3, nil, &length, nil, 0) == 0, length > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&name, 3, &buffer, &length, nil, 0) == 0, length > MemoryLayout<Int32>.size else { return nil }
        let count = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < length, buffer[index] != 0 { index += 1 }
        while index < length, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < length {
            let end = buffer[index..<length].firstIndex(of: 0) ?? length
            arguments.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments.count == count ? arguments : nil
    }
}
