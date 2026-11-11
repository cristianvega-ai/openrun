import Darwin

/// Which terminal sessions still have a live process.
///
/// No new session can take the number of a terminal session while a process
/// of it lives (see `TerminalSessionProcesses`). So the session process can
/// keep the number of an ended session until this finds none of its
/// processes, and a process that reports that number belongs to it.
public enum TerminalSessionCensus {
    /// The numbers among `sessionIdentifiers` that a live process has as its
    /// terminal session, or nil when the system cannot list the processes.
    /// `getsid` fails for a zombie, so a zombie counts as no process.
    public static func liveSessions(among sessionIdentifiers: Set<pid_t>) -> Set<pid_t>? {
        guard !sessionIdentifiers.isEmpty else { return [] }
        guard let identifiers = TerminalSessionProcesses.allProcessIdentifiers() else { return nil }
        var live: Set<pid_t> = []
        for identifier in identifiers where identifier > 0 {
            let session = getsid(identifier)
            if sessionIdentifiers.contains(session) { live.insert(session) }
        }
        return live
    }
}
