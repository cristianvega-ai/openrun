import Darwin

/// The processes of the terminal session that a program leads.
///
/// `forkpty` makes the program the leader of a new session, so the session
/// identifier is the program's process identifier. Every process that the
/// program starts stays in that session, also one that moves to another
/// process group, until it starts a session of its own. Kill and shutdown end
/// all of them, as the owner decided. A process that starts a session of its
/// own escapes.
///
/// Darwin lists no processes by session: `sysctl` with `KERN_PROC_SESSION`
/// fails with ENOENT on macOS. So this lists every process and asks each one
/// for its session.
///
/// A session identifier is the process identifier of the process that made
/// the session (`setsid`), and XNU gives a new process an identifier only when
/// no process, also a zombie, uses that number as its process, process group
/// or session identifier (`forkproc` in bsd/kern/kern_fork.c, which keeps the
/// rule of the 4.4BSD `fork`). So while one process of this session lives, no
/// other session can have its number, and a process that reports this session
/// identifier belongs to this session. The check runs right before each
/// signal. A process that ended in between, and whose identifier went to
/// another program, then fails the check instead of getting the signal.
struct TerminalSessionProcesses {
    /// A live process of the session. Zombies are left out: they have ended,
    /// and no signal reaches them.
    struct Member: Equatable {
        let processIdentifier: pid_t
        let groupIdentifier: pid_t
        /// A stopped process acts on a signal only after SIGCONT.
        let isStopped: Bool
    }

    /// The system could not list the processes.
    struct ListingFailed: Error {}

    let sessionIdentifier: pid_t
    /// Reads every process identifier, or nil when the system fails. Only a
    /// test replaces it, to make the listing fail.
    var listProcessIdentifiers: () -> [pid_t]? = TerminalSessionProcesses.allProcessIdentifiers

    /// The live processes of the session now. An empty list means that the
    /// session has none. A failed process list is not an empty one: nobody
    /// knows then what the session holds.
    ///
    /// - Throws: `ListingFailed` when the process list cannot be read.
    func members() throws -> [Member] {
        guard let identifiers = listProcessIdentifiers() else { throw ListingFailed() }
        return identifiers.compactMap(member(withIdentifier:))
    }

    /// Sends `signal` to each process group that `members` belong to, the
    /// group of the session leader first, as a terminal sends SIGHUP to its
    /// foreground group first.
    ///
    /// A group gets the signal only when one of its members is still in this
    /// session and in that group right before the signal. A group cannot leave
    /// its session, and its identifier is not reused while it has a member.
    func sendToEachGroup(_ signal: Int32, of members: [Member]) {
        let groups = Dictionary(grouping: members, by: \.groupIdentifier)
        let order = groups.keys.sorted { first, second in
            if first == sessionIdentifier || second == sessionIdentifier { return first == sessionIdentifier }
            return first < second
        }
        for group in order {
            let vouched = groups[group, default: []].contains { member in
                isInSession(member.processIdentifier) && getpgid(member.processIdentifier) == group
            }
            if vouched { killpg(group, signal) }
        }
    }

    /// Sends `signal` to each of `members` that is still in this session right
    /// before the signal. Returns how many processes took it.
    @discardableResult
    func send(_ signal: Int32, to members: [Member]) -> Int {
        var delivered = 0
        for member in members where isInSession(member.processIdentifier) {
            if kill(member.processIdentifier, signal) == 0 { delivered += 1 }
        }
        return delivered
    }

    // MARK: - Private

    /// `getsid` fails for a zombie and for a process that is gone.
    private func isInSession(_ processIdentifier: pid_t) -> Bool {
        processIdentifier > 0 && getsid(processIdentifier) == sessionIdentifier
    }

    private func member(withIdentifier processIdentifier: pid_t) -> Member? {
        guard isInSession(processIdentifier) else { return nil }
        let group = getpgid(processIdentifier)
        guard group > 0 else { return nil }
        // The state is only a hint for SIGCONT. A process that the system
        // does not describe to this user still takes the other signals.
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let described = proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &information, size) == size
        return Member(
            processIdentifier: processIdentifier,
            groupIdentifier: group,
            isStopped: described && information.pbi_status == UInt32(SSTOP)
        )
    }

    /// Every process identifier of the system. The list can change while it is
    /// read, so the buffer has room to spare, and grows when it fills up. Nil
    /// means that the list failed.
    private static func allProcessIdentifiers() -> [pid_t]? {
        var capacity = Int(max(proc_listallpids(nil, 0), 0)) + 256
        for _ in 0..<4 {
            var identifiers = [pid_t](repeating: 0, count: capacity)
            let count = identifiers.withUnsafeMutableBytes { buffer in
                proc_listallpids(buffer.baseAddress, Int32(buffer.count))
            }
            guard count >= 0 else { return nil }
            if Int(count) < capacity {
                return Array(identifiers.prefix(Int(count)))
            }
            capacity *= 2
        }
        return nil
    }
}
