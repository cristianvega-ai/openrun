import Darwin
import Dispatch
import PseudoTerminal

/// Waits for the end of a program that leads its own process group, ends
/// the rest of the group, and then reaps the program.
///
/// Until the reap, the zombie of the program keeps its number, which is
/// also the number of the group, so a signal to the group cannot reach
/// another program. The processes left in the group, such as a server that
/// an agent started, get SIGTERM, and SIGKILL after one second. Everything
/// here belongs to `queue`.
final class ProcessGroupReaper: @unchecked Sendable {
    static let gracePeriodNanoseconds: UInt64 = 1_000_000_000
    static let killingLimitNanoseconds: UInt64 = 2_000_000_000
    let processIdentifier: pid_t
    private let queue: DispatchQueue
    private let onExit: (ProgramExit) -> Void
    private var source: DispatchSourceProcess?
    private(set) var hasReaped = false

    init(processIdentifier: pid_t, queue: DispatchQueue, onExit: @escaping (ProgramExit) -> Void) {
        self.processIdentifier = processIdentifier
        self.queue = queue
        self.onExit = onExit
    }

    func start() {
        let watcher = DispatchSource.makeProcessSource(identifier: processIdentifier, eventMask: .exit, queue: queue)
        watcher.setEventHandler { [self] in checkExit() }
        source = watcher
        watcher.resume()
        // The program may have ended before the watcher existed.
        checkExit()
    }

    /// Sends `signal` to the group while the program is not reaped.
    func signalGroup(_ signal: Int32) { if !hasReaped { killpg(processIdentifier, signal) } }

    /// Looks whether the program ended, without reaping it.
    private func checkExit() {
        guard source != nil else { return }
        var information = siginfo_t()
        var result: Int32
        repeat {
            result = waitid(P_PID, id_t(processIdentifier), &information, WEXITED | WNOHANG | WNOWAIT)
        } while result < 0 && errno == EINTR
        // The event can come before the program can be waited for, and it
        // comes once. After another error, such as ECHILD, the reap tells.
        // `waitid` on macOS also reports a stopped or continued program, and
        // that is no end.
        let ended = information.si_pid != 0 && [CLD_EXITED, CLD_KILLED, CLD_DUMPED].contains(information.si_code)
        if result == 0, !ended {
            queue.asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in checkExit() }
            return
        }
        source?.cancel()
        source = nil
        endGroup(since: DispatchTime.now().uptimeNanoseconds, terminated: false)
    }

    private func endGroup(since start: UInt64, terminated: Bool) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        guard Self.groupHasLiveMembers(processIdentifier), elapsed < Self.killingLimitNanoseconds else {
            reap()
            return
        }
        if !terminated {
            killpg(processIdentifier, SIGTERM)
            killpg(processIdentifier, SIGCONT)
        } else if elapsed >= Self.gracePeriodNanoseconds {
            killpg(processIdentifier, SIGKILL)
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(20)) { [self] in endGroup(since: start, terminated: true) }
    }

    /// Never blocks the queue: the program has ended, so the wait returns at
    /// once, and a wait that finds nothing tries again a moment later.
    private func reap() {
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(processIdentifier, &status, WNOHANG) } while result < 0 && errno == EINTR
        if result == 0 {
            queue.asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in reap() }
            return
        }
        hasReaped = true
        // The macros WIFEXITED and WTERMSIG are not available to Swift. On a
        // failed wait the status is lost, and 127 says that it is unknown.
        let signal = status & 0x7f
        onExit(result < 0 ? .exited(status: 127) : signal == 0 ? .exited(status: (status >> 8) & 0xff) : .signaled(signal: signal))
    }

    /// Whether a process other than the zombie of the leader is in the
    /// group. When the list fails, the group counts as live, and the time
    /// limit ends the wait.
    static func groupHasLiveMembers(_ group: pid_t) -> Bool {
        var identifiers = [pid_t](repeating: 0, count: 1_024)
        let count = identifiers.withUnsafeMutableBytes { proc_listpgrppids(group, $0.baseAddress, Int32($0.count)) }
        guard count >= 0 else { return true }
        return identifiers.prefix(Int(count)).contains { member in
            guard member > 0, member != group, getpgid(member) == group else { return false }
            var information = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            return proc_pidinfo(member, PROC_PIDTBSDINFO, 0, &information, size) == size && information.pbi_status != UInt32(SZOMB)
        }
    }
}
