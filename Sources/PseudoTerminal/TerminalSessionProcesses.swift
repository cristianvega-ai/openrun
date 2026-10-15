import Darwin

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
