import Darwin

/// The parents of a process, for the rule that a program which an agent of
/// a thread started may not use the threads (decision of 2026-11-10).
enum ProcessAncestry {
    /// The most parents that the walk follows. A chain is seldom longer
    /// than ten, and a walk must end also when the process list changes
    /// under it.
    static let depthLimit = 64

    /// The process among `candidates` that is `process` itself or one of
    /// its parents, or nil. A process that asked for a new parent, such as
    /// a daemon, has left its agent, as a process that starts a session of
    /// its own leaves its terminal session.
    static func ancestor(of process: pid_t, among candidates: Set<pid_t>) -> pid_t? {
        var current = process
        for _ in 0..<depthLimit where current > 1 {
            if candidates.contains(current) { return current }
            guard let parent = parent(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func parent(of process: pid_t) -> pid_t? {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(process, PROC_PIDTBSDINFO, 0, &information, size) == size else { return nil }
        return pid_t(information.pbi_ppid)
    }
}
