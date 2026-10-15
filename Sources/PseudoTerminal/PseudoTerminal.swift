import Darwin
import Dispatch

/// A program running on a new pseudo terminal.
///
/// The program is a session leader, and the pseudo terminal is its controlling
/// terminal, so a shell can run jobs and the kernel sends hang-up and resize
/// signals the way a real terminal would.
///
/// All methods can be called from any thread. The object closes its
/// descriptor once, when the program has ended and all output has been read.
public final class PseudoTerminal: @unchecked Sendable {
    /// The process identifier of the program. It is also the identifier of the
    /// program's process group and of its terminal session.
    public let processIdentifier: pid_t

    /// The device path of the terminal, such as `/dev/ttys004`. Other programs
    /// can open it to read the terminal's settings.
    public let terminalPath: String

    /// The bytes the program writes, in order. The stream finishes after the
    /// last byte of a program that has ended, and before `waitForExit` returns.
    /// Only one task may read it.
    public let output: AsyncStream<[UInt8]>

    private static let readChunkSize = 64 * 1024
    /// The status reported when `waitpid` fails and the real status is
    /// unknown. A shell's `wait` reports 127 for a process whose status it
    /// does not know. A clean 0 would claim a success that nobody saw.
    static let unknownExitStatus: Int32 = 127
    /// How long `terminate` goes on killing processes that a signal reaches
    /// and that do not end, such as one that keeps starting new ones.
    static let killingLimit: Duration = .seconds(1)

    private let queue = DispatchQueue(label: "PseudoTerminal")
    private let outputContinuation: AsyncStream<[UInt8]>.Continuation

    // Everything below belongs to `queue`. No other thread touches it.
    private var master: Int32
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var exitSource: DispatchSourceProcess?
    private var writeSourceIsSuspended = true
    private var sourcesStillUsingMaster = 2
    /// Input that has not gone to the terminal yet. See `InputBacklog`.
    private var input = InputBacklog()
    private var exit: ProgramExit?
    private var exitWaiters: [CheckedContinuation<ProgramExit, Never>] = []

    /// Starts the program.
    public init(launching launch: ProgramLaunch) throws {
        let started = try launch.start()
        master = started.masterDescriptor
        processIdentifier = started.processIdentifier
        terminalPath = started.terminalPath
        (output, outputContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        startWatching()
    }


    /// Sends bytes to the program at once. It is meant for a terminal's answer
    /// to a query of the program, such as a cursor position report.
    ///
    /// The call never waits: a terminal answers while it parses output, and
    /// parsing must not stop in the middle of a write. The bytes join the
    /// backlog even when the backlog is full, and count as answers. When typed
    /// input waits for room, the bytes go in right behind it, in the order a
    /// real terminal would send them. The reader of the output calls
    /// `waitForAnswerRoom` between chunks, which stops a program that asks
    /// without end and never reads from growing the backlog without limit.
    /// Typed input goes through `type` instead.
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async {
            guard !self.input.isClosed else { return }
            self.input.addAnswer(bytes)
            self.pumpInput()
        }
    }

    /// Tells the program its terminal has a new size. The kernel sends it
    /// SIGWINCH.
    public func resize(to size: PseudoTerminalSize) throws {
        try queue.sync {
            guard exit == nil, master >= 0 else { return }
            try Self.setSize(size, on: master)
        }
    }

    /// Waits for the program to end and returns how.
    public func waitForExit() async -> ProgramExit {
        await withCheckedContinuation { continuation in
            queue.async {
                if let exit = self.exit {
                    continuation.resume(returning: exit)
                } else {
                    self.exitWaiters.append(continuation)
                }
            }
        }
    }

    /// Ends the program and every other process of its terminal session.
    ///
    /// SIGHUP goes to the program's process group, which is what a closed
    /// terminal window sends, and then to each other process group of the
    /// session. A group with a stopped process also gets SIGCONT, because a
    /// stopped process acts on the hang-up only when it runs. After
    /// `gracePeriod`, SIGKILL goes to every process of the session that is
    /// still alive, also when the program itself has already ended. Returns
    /// after the program has ended.
    ///
    /// A process that started a session of its own is not in this session and
    /// keeps running. A program that has already ended by itself leaves its
    /// background processes running.
    ///
    /// When the system cannot list the processes, nobody knows what the
    /// session holds. Then `terminate` signals the program's process group
    /// instead, and keeps waiting and signalling until the grace period and
    /// the killing limit have passed.
    public func terminate(gracePeriod: Duration = .seconds(1)) async {
        await terminate(gracePeriod: gracePeriod, session: TerminalSessionProcesses(sessionIdentifier: processIdentifier))
    }

    /// `session` is a parameter only so that a test can make the listing of
    /// processes fail.
    func terminate(gracePeriod: Duration, session: TerminalSessionProcesses) async {
        // Until the program is reaped, its identifier, and so the session
        // identifier, cannot belong to anything else. After that, the number
        // stays this session's only while a process of the session lives. So
        // the work starts only while the program is unreaped, looks again at
        // least every 20 milliseconds, and stops for good once the session has
        // no process left. Another session could take the number only after
        // every other process identifier, about 100,000 of them, was handed
        // out in between.
        guard !hasExited else { return }
        // Nil means that the list failed and the members are unknown.
        var members = try? session.members()
        if let known = members {
            session.sendToEachGroup(SIGHUP, of: known)
            session.sendToEachGroup(SIGCONT, of: known.filter(\.isStopped))
        } else {
            sendSignalToProgramGroup(SIGHUP)
        }
        let deadline = ContinuousClock.now + gracePeriod
        while members.map({ !$0.isEmpty }) ?? true || !hasExited, ContinuousClock.now < deadline {
            // A cancelled task must not turn this wait into a busy loop, and
            // a cancelled task makes Task.sleep return at once.
            await Self.pause(for: .milliseconds(20))
            members = try? session.members()
            if members == nil { sendSignalToProgramGroup(SIGHUP) }
        }
        // A process can start another one while the first is killed, so look
        // again until no process is left that a signal can reach.
        let killingDeadline = ContinuousClock.now + Self.killingLimit
        while members.map({ !$0.isEmpty }) ?? true, ContinuousClock.now < killingDeadline {
            if let known = members {
                guard session.send(SIGKILL, to: known) > 0 else { break }
            } else {
                sendSignalToProgramGroup(SIGKILL)
            }
            await Self.pause(for: .milliseconds(20))
            members = try? session.members()
        }
        // The program's own group gets SIGKILL in any case while the program
        // is unreaped, so the wait below ends even when the list of processes
        // missed the program.
        if !hasExited {
            sendSignalToProgramGroup(SIGKILL)
        }
        _ = await waitForExit()
    }

    // MARK: - Starting

    private static func setSize(_ size: PseudoTerminalSize, on descriptor: Int32) throws {
        var windowSize = winsize(ws_row: size.rows, ws_col: size.columns, ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(descriptor, TIOCSWINSZ, &windowSize) == 0 else { throw PseudoTerminalError.failure(of: "ioctl") }
    }

    private func startWatching() {
        let reader = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        reader.setEventHandler { [self] in readAvailableOutput() }
        reader.setCancelHandler { [self] in releaseMaster() }
        readSource = reader

        let writer = DispatchSource.makeWriteSource(fileDescriptor: master, queue: queue)
        writer.setEventHandler { [self] in pumpInput() }
        writer.setCancelHandler { [self] in releaseMaster() }
        writeSource = writer

        let watcher = DispatchSource.makeProcessSource(identifier: processIdentifier, eventMask: .exit, queue: queue)
        watcher.setEventHandler { [self] in reapIfExited(retryingWhileExiting: true) }
        exitSource = watcher

        reader.resume()
        watcher.resume()
        // The program may have ended before the watcher existed.
        queue.async { self.reapIfExited() }
    }

    // MARK: - Output (on the queue)

    private func readAvailableOutput(honoringBackpressure: Bool = true) {
        guard master >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                outputContinuation.yield(Array(buffer[0..<count]))
                continue
            }
            if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
                // Every holder of the terminal closed it. The source would
                // fire forever, so stop it. The exit watcher finishes the job.
                readSource?.cancel()
            }
            if count < 0 && errno == EINTR { continue }
            return
        }
    }

    // MARK: - Input (on the queue)


    /// Moves typed input that waits into the backlog while it fits, and
    /// writes the backlog to the terminal while it takes bytes.
    private func pumpInput() {
        var notices: [InputBacklog.Notice] = []
        var progressed = true
        while progressed {
            notices += input.admitWaiting()
            // Writing makes room, and room can let more waiting input in.
            progressed = writePendingInput(notices: &notices) && input.hasWaitingInput
        }
        // The write source fires whenever the terminal can take bytes, so it
        // runs only while input waits.
        if input.isEmpty, !writeSourceIsSuspended {
            writeSource?.suspend()
            writeSourceIsSuspended = true
        } else if !input.isEmpty, writeSourceIsSuspended {
            writeSource?.resume()
            writeSourceIsSuspended = false
        }
        notices.forEach { $0.deliver() }
    }

    /// Writes from the front of the backlog until the terminal takes no more.
    /// Returns whether any byte went out.
    private func writePendingInput(notices: inout [InputBacklog.Notice]) -> Bool {
        var wroteAny = false
        while let front = input.front, master >= 0 {
            let count = front.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
            if count > 0 {
                wroteAny = true
                input.removeFromFront(count)
            } else if count < 0 && errno == EINTR {
                continue
            } else if count < 0 && errno == EAGAIN {
                break
            } else {
                // Nobody holds the terminal open any more, so no input can
                // reach the program again.
                notices += input.close()
                break
            }
        }
        return wroteAny
    }

    /// Ends all input: the backlog goes, and all typed input that waits fails.
    private func closeInput() {
        input.close().forEach { $0.deliver() }
    }

    // MARK: - Exit (on the queue)

    private func reapIfExited(retryingWhileExiting: Bool = false) {
        guard exit == nil else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(processIdentifier, &status, WNOHANG)
        } while result < 0 && errno == EINTR
        guard result != 0 else {
            // The system reports the exit before the program counts as ended.
            // A session leader with a controlling terminal takes longer, because
            // the kernel hangs up the terminal first. The event comes only once,
            // so ask again until the program can be reaped.
            if retryingWhileExiting {
                queue.asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in
                    reapIfExited(retryingWhileExiting: true)
                }
            }
            return
        }
        // On another waitpid error, such as ECHILD after another waiter reaped
        // the child, the status is lost and no later call can learn it. Report
        // an unknown status instead of waiting forever.
        let reason = result < 0 ? ProgramExit.exited(status: Self.unknownExitStatus) : ProgramExit(waitStatus: status)

        // Output the program wrote before it ended can still sit in the
        // kernel buffer. Deliver it before the stream finishes.
        readAvailableOutput(honoringBackpressure: false)
        outputContinuation.finish()
        exit = reason
        closeInput()

        exitSource?.cancel()
        exitSource = nil
        readSource?.cancel()
        if writeSourceIsSuspended {
            writeSource?.resume()
            writeSourceIsSuspended = false
        }
        writeSource?.cancel()
        for waiter in exitWaiters {
            waiter.resume(returning: reason)
        }
        exitWaiters.removeAll()
    }

    // The descriptor closes when the last source that watched it is gone,
    // because closing it earlier would break a source that still runs.
    private func releaseMaster() {
        sourcesStillUsingMaster -= 1
        guard sourcesStillUsingMaster == 0, master >= 0 else { return }
        close(master)
        master = -1
        readSource = nil
        writeSource = nil
    }

    // MARK: - Signals

    /// The descriptor of the controlling side, or -1 once it is closed. Tests
    /// use it to check that the descriptor does not outlive the program.
    var masterDescriptorForTesting: Int32 {
        queue.sync { master }
    }

    private var hasExited: Bool {
        queue.sync { exit != nil }
    }

    private static func pause(for duration: Duration) async {
        let parts = duration.components
        let delay = DispatchTimeInterval.nanoseconds(Int(parts.seconds) * 1_000_000_000 + Int(parts.attoseconds / 1_000_000_000))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { continuation.resume() }
        }
    }

    // The program is reaped on the queue, so while `exit` is empty the
    // process identifier cannot belong to another process.
    private func sendSignalToProgramGroup(_ signal: Int32) {
        queue.sync {
            guard exit == nil else { return }
            killpg(processIdentifier, signal)
        }
    }
}
