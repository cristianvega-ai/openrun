import Foundation
import GitBranch
import PseudoTerminal
import SessionProtocol
import Synchronization
import TerminalEmulation
import TerminalTheme

/// One program on one pseudo terminal, with the terminal state that lets a
/// client attach at any moment.
///
/// The session is an actor, so its own serial context orders everything that
/// touches the screen: output from the program, attaching, resizing and
/// reading. That ordering is what makes attaching free of gaps and repeats.
actor Session {
    /// The line limit of the scrollback of a session, unless the setting
    /// `scrollback-limit` names another.
    static let scrollbackLimit = 10_000

    private(set) var summary: SessionSummary
    private let pseudoTerminal: PseudoTerminal
    /// The program leads its own terminal session, so the identifier of that
    /// terminal session is this number (see `SessionRegistry.place(of:)`).
    nonisolated var programProcessIdentifier: pid_t { pseudoTerminal.processIdentifier }
    private let terminal: Terminal
    /// Writes the program's output to the terminal, and finds its prompts.
    private let prompts: ShellPromptTracker
    private var clients: [ObjectIdentifier: ClientConnection] = [:]
    /// The attached clients that write raw output to a real terminal.
    private var relayingClients: Set<ObjectIdentifier> = []
    /// The attached clients that asked to hear of each new size.
    private var clientsThatReceiveSizeChanges: Set<ObjectIdentifier> = []
    private var clientsThatWaitForOutputRoom: Set<ObjectIdentifier> = []
    private let replyGate: ReplyGate
    /// A new size that waits for the answer of a shell's line editor.
    private var lineEditorWait = LineEditorWait()
    /// How long a new size waits for the answer. zsh and bash answer within
    /// milliseconds, unless the prompt runs a slow command. At the limit the
    /// screen takes the size, and the wait goes on for four more limits.
    private let answerTimeLimit: Duration
    /// The bytes of program output that the terminal model has parsed.
    private var parsedByteCount = 0
    private var isFinished = false
    private var isEnding = false
    private var programExit: SessionExit?
    private var runTask: Task<Void, Never>?
    private let onFinish: @Sendable (UUID) async -> Void
    /// Where the watchers of the sessions hear of this session. Nil for a
    /// session that a test makes alone.
    private let changes: SessionChangeFeed?
    /// What the terminal reported while it parsed the last piece of output.
    private let terminalEvents = TerminalEvents()
    /// libghostty-vt reports no OSC 99, so the session finds it itself.
    private var kittyNotifications = KittyNotificationScanner()
    /// Whether the session works. See `SessionActivity`.
    private var activity = SessionActivity()
    /// Looks at the foreground while output or input comes.
    private var factsRefresh: Task<Void, Never>?
    /// How often the session looks at the folder, the branch, the foreground
    /// program and the mode of the terminal while output or input comes.
    static let factsRefreshInterval: Duration = .seconds(1)
    /// The summary that the watchers have, and when it went out.
    private var publishedSummary: SessionSummary?
    private var publishedAt: ContinuousClock.Instant?
    private var waitingPublish: Task<Void, Never>?
    /// The shortest time between two changes of one session. A program can
    /// set its title many times a second, and each change goes to each
    /// watcher, so the watchers get the newest summary at most this often.
    static let changeInterval: Duration = .milliseconds(250)

    /// Creates the terminal, then starts the program.
    ///
    /// The program starts last, so nothing can fail after it runs. A failure
    /// before it leaves no program running without a session.
    ///
    /// - Parameters:
    ///   - openingNotice: A line that shows above the first output of
    ///     the program, also for a client that attaches later.
    ///   - answerTimeLimit: How long a new size waits for a line editor.
    ///   - installReplyHandler: Installs the handler on the terminal. Tests
    ///     replace it to make the installation fail, or to fix the scheme.
    init(
        summary: SessionSummary,
        launch: ProgramLaunch,
        changes: SessionChangeFeed? = nil,
        scrollbackLimit: Int = Session.scrollbackLimit,
        openingNotice: String? = nil,
        onFinish: @escaping @Sendable (UUID) async -> Void,
        answerTimeLimit: Duration = .milliseconds(500),
        installReplyHandler: (Terminal, @escaping TerminalReplyHandler) throws -> Void = { try Session.installReplies(on: $0, handler: $1) }
    ) throws {
        self.summary = summary
        self.onFinish = onFinish
        self.changes = changes
        self.answerTimeLimit = answerTimeLimit
        let gate = ReplyGate()
        replyGate = gate
        terminal = try Terminal(size: TerminalSize(summary.size), scrollbackLimit: scrollbackLimit)
        if let openingNotice { terminal.write(Array("\u{1B}[2m\(openingNotice)\u{1B}[0m\r\n".utf8)) }
        prompts = ShellPromptTracker(terminal: terminal)
        try terminal.setEventHandler(terminalEvents.handler)
        // The terminal answers queries such as "where is the cursor", unless a
        // client's real terminal answers them. A client's copy of the screen
        // has no handler, so the real terminal is the only other source.
        try installReplyHandler(terminal) { bytes in gate.deliver(bytes) }
        let pseudoTerminal = try PseudoTerminal(launching: launch)
        self.pseudoTerminal = pseudoTerminal
        gate.connect(pseudoTerminal)
    }

    /// Answers color queries with the Graphite colors of the appearance,
    /// the colors that the view draws with, so programs choose readable colors.
    static func installReplies(
        on terminal: Terminal, handler: @escaping TerminalReplyHandler,
        colorScheme: @escaping @Sendable () -> TerminalColorScheme = { TerminalColorScheme.current() }
    ) throws {
        try terminal.setReplyHandler(handler, colorScheme: colorScheme) { TerminalTheme.graphite(for: $0).defaultColors }
    }

    /// Decides whether the session process answers terminal queries.
    ///
    /// The handler asks the gate while the session parses the bytes of a query.
    /// The session parses on its own serial context, which also runs attach
    /// and detach. So each query meets exactly one state of the client list:
    /// the one at the moment its bytes are parsed. A client that attaches later
    /// does not see that query, because its snapshot holds the screen and not
    /// the bytes. A client that is attached receives the bytes and its real
    /// terminal answers.
    ///
    /// The gate also holds the program's pseudo terminal, because the handler
    /// is installed before the program starts. The terminal parses output
    /// only after that, so no answer comes before the program is connected.
    private final class ReplyGate: Sendable {
        private struct State {
            var isClosed = false
            var program: PseudoTerminal?
        }

        private let state = Mutex(State())

        func deliver(_ bytes: [UInt8]) {
            let program = state.withLock { $0.isClosed ? nil : $0.program }
            program?.write(bytes)
        }

        func connect(_ program: PseudoTerminal) { state.withLock { $0.program = program } }
        func close(_ shouldClose: Bool) { state.withLock { $0.isClosed = shouldClose } }
    }

    /// Starts reading the program's output. Call once, right after creating.
    func start() {
        readForeground()
        summary.isInProgress = activity.isInProgress(at: .now)
        (publishedSummary, publishedAt) = (summary, .now)
        changes?.add(summary)
        runTask = Task { await self.run() }
        // A program can change the mode of the terminal before it writes
        // anything, so the session looks once more.
        refreshFactsWhileActive()
    }

    /// What became of a request to attach.
    enum Attachment {
        case attached
        /// The session ended before the request.
        case sessionEnded
        /// The client is not attached, for the reason in the failure.
        case refused(SessionFailure)
    }

    /// Takes a snapshot and registers the client in one step.
    ///
    /// Nothing else runs on the session between the snapshot and the
    /// registration, because the session is an actor and this method does not
    /// wait. Output that arrived earlier is inside the snapshot. Output that
    /// arrives later goes to the client's queue behind the snapshot.
    ///
    /// The snapshot travels in one frame. A larger snapshot loses its oldest
    /// scrollback until it fits. When the screens alone do not fit, the
    /// client is refused before `attached`. A capture that throws also
    /// ends the attach. In both cases the terminal model and the program's
    /// terminal go back to the previous size, and no client hears of a size
    /// change. The program may see the new size for a short time. When the
    /// terminal model or the program's terminal refuses the previous size,
    /// both copies keep the new size, and the clients that asked hear of it.
    /// After a successful attach, the other clients that asked hear of a
    /// new size once. A resize that waits for a line editor applies before
    /// the attach, without the answer, because the attach comes later. It
    /// keeps the rows of the prompt, as at the time limit.
    ///
    /// A client that relays raw output has a real terminal that answers queries.
    /// While one is attached, the session process sends no replies. Two such
    /// clients answer the same query twice. That limit is accepted for now.
    func attach(_ client: ClientConnection, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool, waitsForOutputRoom: Bool) throws -> Attachment {
        guard !isFinished else { return .sessionEnded }
        while lineEditorWait.isWaiting { finishWait(keeping: keepingWithoutAnswer()) }
        let previousSize = summary.size
        defer { if summary.size != previousSize { announceSize(changedBy: ObjectIdentifier(client)) } }
        try apply(size)
        let snapshot: TerminalSnapshot?
        do {
            snapshot = try TerminalSnapshot(capturing: terminal, byteLimit: MessageFrame.maximumPayloadLength)
        } catch {
            // The capture failed, so the client does not attach and its size does not stay.
            _ = try? apply(previousSize)
            throw error
        }
        guard let snapshot else {
            // The client does not attach, so its size does not stay either.
            _ = try? apply(previousSize)
            return .refused(SessionFailure(
                reason: .invalidRequest,
                message: "The screen of the session does not fit in one frame of \(MessageFrame.maximumPayloadLength / 1_048_576) MiB, even without scrollback. Attach with fewer columns or rows."
            ))
        }
        client.send(.attached(summary))
        // A snapshot of a full, colorful scrollback can be larger than the
        // limit for output that waits, so it does not count. The output that
        // follows it does.
        if waitsForOutputRoom { client.allowLargeSnapshotRestoration(byteCount: snapshot.bytes.count) }
        client.send(.snapshot(Data(snapshot.bytes)), countsTowardOutputLimit: false)
        clients[ObjectIdentifier(client)] = client
        if relaysRawOutput { relayingClients.insert(ObjectIdentifier(client)) }
        if receivesSizeChanges { clientsThatReceiveSizeChanges.insert(ObjectIdentifier(client)) }
        if waitsForOutputRoom { clientsThatWaitForOutputRoom.insert(ObjectIdentifier(client)) }
        updateReplyGate()
        return .attached
    }

    func detach(_ client: ClientConnection) {
        clients[ObjectIdentifier(client)] = nil
        relayingClients.remove(ObjectIdentifier(client))
        clientsThatReceiveSizeChanges.remove(ObjectIdentifier(client))
        clientsThatWaitForOutputRoom.remove(ObjectIdentifier(client))
        lineEditorWait.forget(ObjectIdentifier(client))
        client.refuseOutputRoomWait()
        updateReplyGate()
    }

    /// Types bytes into the program.
    ///
    /// Waits while the program's input backlog is full. The wait happens
    /// outside the actor, so the session goes on with its output, attaching,
    /// and ending meanwhile.
    ///
    /// - Throws: `PseudoTerminalError.programEnded` when the program ends
    ///   before the bytes are in the backlog.
    nonisolated func type(_ bytes: [UInt8]) async throws {
        try await pseudoTerminal.type(bytes)
    }

    /// Types the bytes of an attached client behind its earlier input, and
    /// returns at once. `whenSettled` runs once the bytes are in the backlog,
    /// or will never get there. See `PseudoTerminal.type(_:from:whenSettled:)`.
    nonisolated func type(_ bytes: [UInt8], from owner: ObjectIdentifier, whenSettled: @escaping @Sendable () -> Void) {
        pseudoTerminal.type(bytes, from: owner, whenSettled: whenSettled)
    }

    /// Drops the input of a client that left and that has not gone to the
    /// program yet, so the client holds no memory after it has gone.
    nonisolated func withdrawTypedInput(from owner: ObjectIdentifier) {
        pseudoTerminal.withdrawTypedInput(from: owner)
    }

    /// Resizes the program's terminal and the session's copy of it. The last
    /// client to resize wins, and the other clients that asked hear of it.
    ///
    /// While a shell edits a command line, the copy and the clients take a
    /// new width where the shell has erased its lines (see `LineEditorWait`).
    func resize(to size: SessionSize, from requester: ClientConnection, confirmsResize: Bool = false) throws {
        let request = LineEditorWait.Request(
            size: size, requester: ObjectIdentifier(requester), confirms: confirmsResize,
            reportsItself: relayingClients.contains(ObjectIdentifier(requester))
        )
        guard !lineEditorWait.isWaiting else {
            // A size of zero changes nothing, as it does without a wait, so it
            // must not replace a waiting resize.
            guard size.columns > 0, size.rows > 0 else {
                if confirmsResize { lineEditorWait.owe(ObjectIdentifier(requester)) }
                return
            }
            // The request gets no answer later, so a refused size fails now.
            try Terminal.validate(TerminalSize(size))
            lineEditorWait.queue(request)
            return
        }
        try change(by: request)
    }

    /// The text on the screen, or on the screen and above it.
    func screenText(includeScrollback: Bool) throws -> String {
        let bytes = try terminal.formatted(.plainText, extent: includeScrollback ? .withScrollback : .visible)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Ends the program and waits until the session has told its clients and
    /// left the list. Returns how the program ended.
    @discardableResult
    func terminate() async -> SessionExit {
        isEnding = true
        for client in clients.values { client.refuseOutputRoomWait() }
        await pseudoTerminal.terminate()
        await runTask?.value
        if let programExit { return programExit }
        return SessionExit(await pseudoTerminal.waitForExit())
    }

    // MARK: - Private

    private func run() async {
        let exitWatcher = Task { [weak self, pseudoTerminal] in
            _ = await pseudoTerminal.waitForExit()
            await self?.programDidExit()
        }
        for await bytes in pseudoTerminal.output {
            // Output that arrives while the session ends needs no parsing. The
            // screen is about to disappear, and parsing could delay a shutdown.
            if !isEnding {
                var rest = bytes[...]
                // A new wait can start in `finishWait`. It counts the rest of
                // these bytes as older than its size, so they go through it
                // too: it skips them once, and finds no answer in them.
                while let end = lineEditorWait.end(in: rest) {
                    show(rest[..<end.index])
                    finishWait(keeping: end.erasedLines ? .cursorRow : .nothing)
                    rest = rest[end.index...]
                }
                show(rest)
                await waitForOutputRoom()
            }
            pseudoTerminal.markOutputConsumed(bytes.count)
            // A program that asks questions and never reads the answers waits
            // here, in its own output, instead of growing the input backlog.
            await pseudoTerminal.waitForAnswerRoom()
            // A steady stream never suspends this loop, and the actor would
            // serve nobody else. Yielding lets attach, read and kill run.
            await Task.yield()
        }
        exitWatcher.cancel()
        let exit = SessionExit(await pseudoTerminal.waitForExit())
        programExit = exit
        isFinished = true
        for client in clients.values {
            // The exit status goes out even to a client near its limit.
            client.send(.exited(exit), countsTowardOutputLimit: false)
            client.closeAfterSending()
        }
        clients.removeAll()
        relayingClients.removeAll()
        clientsThatReceiveSizeChanges.removeAll()
        clientsThatWaitForOutputRoom.removeAll()
        updateReplyGate()
        waitingPublish?.cancel()
        factsRefresh?.cancel()
        changes?.end(summary.identifier)
        await onFinish(summary.identifier)
    }

    /// Parses program output and sends it to every client.
    private func show(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty else { return }
        prompts.write(bytes)
        parsedByteCount += bytes.count
        let message = ServerMessage.output(Data(bytes))
        for client in clients.values { client.send(message) }
        summary.lastOutputAt = Date()
        activity.noteOutput(at: .now)
        summary.isInProgress = activity.isInProgress(at: .now)
        if let text = kittyNotifications.notification(in: bytes) { terminalEvents.note(notification: text) }
        takeTerminalEvents()
        publish()
        refreshFactsWhileActive()
    }

    /// Command-K: erases the scrollback, for the session and for each
    /// client, because the erase goes out as output. When a shell waits
    /// at its prompt, the screen goes too, and a form feed makes the
    /// shell draw its prompt again at the top. Any other program keeps
    /// its screen, because it would not draw it again.
    func clearScrollback() {
        let isAtPrompt = waitingLineEditor() != nil
        show(ArraySlice(Array((isAtPrompt ? "\u{1B}[H\u{1B}[2J\u{1B}[3J" : "\u{1B}[3J").utf8)))
        if isAtPrompt { Task { try? await type([0x0C]) } }
    }

    /// Reads the foreground program, its folder, the branch of the folder
    /// and the mode of the terminal. A folder that the system does not
    /// report keeps the last one.
    private func readForeground() {
        let state = pseudoTerminal.foregroundState
        activity.noteForeground(state)
        summary.foregroundProgram = state.map { SessionSummary.boundedText($0.program.name) }
        guard let folder = state?.currentFolder else { return }
        summary.currentFolder = SessionSummary.boundedText(folder)
        summary.branch = GitBranch.name(forFolder: folder).map(SessionSummary.boundedText)
    }

    /// Looks at the foreground once in `factsRefreshInterval` while output
    /// or input comes, and once more after both have been quiet for
    /// `SessionActivity.quietTime`. A silent session costs no work.
    private func refreshFactsWhileActive() {
        guard factsRefresh == nil, !isFinished, !isEnding else { return }
        factsRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.factsRefreshInterval)
                guard let self, await self.refreshFacts() else { return }
            }
        }
    }

    /// Returns whether to look again. The times of the last output and
    /// input go out once the session is quiet.
    private func refreshFacts() -> Bool {
        guard !isFinished, !isEnding else { return false }
        readForeground()
        let now = ContinuousClock.now
        summary.isInProgress = activity.isInProgress(at: now)
        let isQuiet = activity.isQuiet(at: now)
        publish(includingTimes: isQuiet)
        if isQuiet { factsRefresh = nil }
        return !isQuiet
    }

    /// Takes what the terminal reported while it parsed the output. A
    /// notification raises the alert with its text. The bell raises it when
    /// no alert is up, and not right after a typed key.
    private func takeTerminalEvents() {
        if terminalEvents.titleChanged {
            let title = SessionSummary.boundedText(terminal.title)
            summary.title = title.isEmpty ? nil : title
        }
        if let text = terminalEvents.notification {
            summary.alert = SessionAlert(text: text, raisedAt: Date(), source: .terminalNotification)
        } else if terminalEvents.bellRang, summary.alert == nil, activity.bellRaisesAlert(at: .now) {
            summary.alert = SessionAlert(text: "", raisedAt: Date(), source: .bell)
        }
        terminalEvents.reset()
    }

    /// Changes the facts that a client gives, such as the name or the alert.
    /// Returns false when the session has ended.
    func update(_ change: @Sendable (inout SessionSummary) -> Void) -> Bool {
        guard !isFinished else { return false }
        change(&summary)
        publish()
        return true
    }

    /// Notes input. The keys of an attached client end the alert, because
    /// the user is at the session. Text that a program sends does not.
    func noteInput(isTyped: Bool) {
        guard !isFinished else { return }
        activity.noteInput(at: .now, isTyped: isTyped)
        summary.lastInputAt = Date()
        if isTyped { summary.alert = nil }
        publish()
        refreshFactsWhileActive()
    }

    /// Sends the summary to the watchers when a fact of the list changed: at
    /// once, or after `changeInterval`, with the newest facts. The times of
    /// the last output and input, and the size, go out with another change,
    /// or when `includingTimes` says so, so not for each piece of output.
    private func publish(includingTimes: Bool = false) {
        guard let changes, let publishedSummary, waitingPublish == nil, !isFinished else { return }
        guard includingTimes ? summary != publishedSummary : summary.differsInListedFacts(from: publishedSummary) else { return }
        let earliest = (publishedAt ?? .now) + Self.changeInterval
        guard earliest <= .now else {
            waitingPublish = Task { [weak self] in
                try? await Task.sleep(until: earliest, clock: .continuous)
                await self?.publishWaitingSummary()
            }
            return
        }
        (self.publishedSummary, publishedAt) = (summary, .now)
        changes.change(summary)
    }

    private func publishWaitingSummary() {
        waitingPublish = nil
        guard !isFinished, summary != publishedSummary else { return }
        (publishedSummary, publishedAt) = (summary, .now)
        changes?.change(summary)
    }

    private func updateReplyGate() {
        replyGate.close(!relayingClients.isEmpty)
    }

    /// The program ended, so the remaining output gets the normal room
    /// deadline without the snapshot grace.
    private func programDidExit() {
        for client in clients.values { client.programDidExit() }
    }

    /// A fast viewer takes precedence over a client whose queue is full.
    /// Otherwise the program waits. One call is one pause with one deadline,
    /// however many clients are full. Waits that ran one after another would
    /// stop the program for the time limit once for each stalled client.
    func waitForOutputRoom() async {
        var pauseDeadline: ContinuousClock.Instant?
        while !isEnding {
            let counts = clients.compactMapValues(\.queuedOutputBytes)
            let full = clientsThatWaitForOutputRoom.filter { (counts[$0] ?? 0) >= ConnectionLimits.outputHighMark }
            guard let first = full.first, let client = clients[first] else { return }
            let deadline = pauseDeadline ?? .now + ConnectionLimits.outputRoomTimeLimit
            pauseDeadline = deadline
            if counts.contains(where: { $0.key != first && $0.value <= ConnectionLimits.outputLowMark && clients[$0.key]?.hasMadeOutputProgress == true }) {
                client.endForOutputBackpressure()
            } else {
                let otherClients = clients.filter { $0.key != first }.map(\.value)
                for other in otherClients {
                    other.observeOutputProgress { [weak client] in client?.stopWaitingForOutputRoom() }
                }
                await client.waitForOutputRoom(until: deadline) {
                    // Progress can occur before the waiter is installed.
                    if otherClients.contains(where: { ($0.queuedOutputBytes ?? Int.max) <= ConnectionLimits.outputLowMark && $0.hasMadeOutputProgress }) {
                        client.stopWaitingForOutputRoom()
                    }
                }
                for other in otherClients { other.observeOutputProgress(nil) }
            }
        }
    }

    /// A client that draws the screen itself must lay out the output that
    /// follows for the new size. The message goes out before that output.
    /// The requester knows its own size and does not get it.
    private func announceSize(changedBy requester: ObjectIdentifier?, keeping: PromptKeeping = .nothing) {
        for (key, client) in clients where key != requester && clientsThatReceiveSizeChanges.contains(key) {
            client.send(sizeChanged(keeping: keeping))
        }
    }

    private func confirm(_ request: LineEditorWait.Request, keeping: PromptKeeping = .nothing) {
        guard request.confirms, let requester = request.requester else { return }
        clients[requester]?.send(sizeChanged(keeping: keeping))
    }

    /// A client with a copy of the screen keeps what the session's screen kept.
    private func sizeChanged(keeping: PromptKeeping) -> ServerMessage {
        switch keeping {
        case .nothing: .sizeChanged(summary.size)
        case .cursorRow: .sizeChanged(summary.size, keepsCursorAtLineStart: true)
        case .promptRows(let rows): .sizeChanged(summary.size, promptRowsAboveCursor: rows)
        }
    }

    /// The line editor that waits at the cursor: a shell whose prompt the
    /// output shows, also behind ssh, or bash in the foreground. bash turns
    /// on bracketed paste only while it edits a command line, and the program
    /// that reads the keys must be bash itself: an agent or another program
    /// in the foreground draws its own way.
    private func waitingLineEditor() -> LineEditor? {
        guard !terminal.isAlternateScreenActive else { return nil }
        if let prompt = prompts.prompt { return prompt.editor }
        guard terminal.isModeEnabled(.bracketedPaste), let program = pseudoTerminal.foregroundProgram else { return nil }
        return InteractiveShell.lineEditor(of: program)
    }

    /// Applies a resize at once, or starts to wait for a line editor when
    /// the width changes under one. New rows alone reflow no text, so the
    /// editor's count of rows stays right.
    private func change(by request: LineEditorWait.Request) throws {
        let size = request.size
        if size.columns > 0, size.rows > 0, size.columns != summary.size.columns, let editor = waitingLineEditor() {
            try Terminal.validate(TerminalSize(size))
            // The program wrote these bytes before it got the new size.
            let earlierByteCount = pseudoTerminal.writtenOutputByteCount - parsedByteCount
            try pseudoTerminal.resize(to: PseudoTerminalSize(size))
            // A query of the size gets the size that the program has.
            terminal.reportedSize = TerminalSize(size)
            scheduleTimeLimit(of: lineEditorWait.start(request, editor: editor, earlierByteCount: earlierByteCount), after: answerTimeLimit)
            return
        }
        if try apply(size, requesterReportsSize: request.reportsItself) { announceSize(changedBy: request.requester) }
        confirm(request)
        sendOwedSizes()
    }

    /// Tells the clients whose confirmed resize a newer one replaced.
    private func sendOwedSizes(keeping: PromptKeeping = .nothing) {
        for client in lineEditorWait.takeClientsOwedTheSize() {
            clients[client]?.send(sizeChanged(keeping: keeping))
        }
    }

    private func scheduleTimeLimit(of number: Int, after limit: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: limit)
            await self?.answerTimeLimitPassed(number)
        }
    }

    /// The screen takes the size without the answer. The answer is still
    /// due, and the shell draws it for this size. A newer size before it
    /// would make that answer end the newer wait, at the wrong width. So
    /// the wait goes on, for longer than a prompt with a slow command takes.
    private func answerTimeLimitPassed(_ number: Int) {
        guard !isFinished, lineEditorWait.isWaiting, lineEditorWait.number == number else { return }
        guard lineEditorWait.answerIsLate else {
            applyWaitingSize(keeping: keepingWithoutAnswer())
            lineEditorWait.noteLateAnswer()
            return scheduleTimeLimit(of: number, after: answerTimeLimit * 4)
        }
        finishWait(keeping: .nothing)
    }

    /// A size without the shell's answer keeps the rows of a prompt that the
    /// output shows, so the late answer lands on the prompt.
    private func keepingWithoutAnswer() -> PromptKeeping {
        prompts.prompt.map { .promptRows(aboveCursor: $0.rowsAboveCursor) } ?? .nothing
    }

    /// Ends the wait. The terminal model takes the size that the program
    /// has, unless it took it at the time limit. Then the resize that came
    /// during the wait applies.
    ///
    /// - Parameter keeping: What the model keeps of the prompt (see
    ///   `Terminal.resize`). The clients keep what the model kept.
    private func finishWait(keeping: PromptKeeping) {
        guard lineEditorWait.isWaiting else { return }
        let kept = lineEditorWait.answerIsLate ? .nothing : applyWaitingSize(keeping: keeping)
        guard let (_, next) = lineEditorWait.finish() else { return }
        guard let next else { return sendOwedSizes(keeping: kept) }
        do {
            try change(by: next)
        } catch {
            // The size of `next` was checked when it came. When the program's
            // terminal refuses it now, the requester hears of the size in use.
            confirm(next)
            sendOwedSizes()
        }
    }

    /// Gives the terminal model the size that the program has, and tells the
    /// clients, in order with the output. Returns what the model kept.
    @discardableResult
    private func applyWaitingSize(keeping: PromptKeeping) -> PromptKeeping {
        guard let waiting = lineEditorWait.request else { return .nothing }
        terminal.reportedSize = nil
        if !waiting.reportsItself { replyGate.close(false) }
        var kept = PromptKeeping.nothing
        do {
            kept = try prompts.resize(to: TerminalSize(waiting.size), keeping: keeping)
            summary.size = waiting.size
            announceSize(changedBy: waiting.requester, keeping: kept)
        } catch {
            // The size was checked, so only a lack of memory gets here. The
            // program goes back to the size of the model. That size is not
            // new, so the clients have nothing to keep.
            try? pseudoTerminal.resize(to: PseudoTerminalSize(summary.size))
        }
        updateReplyGate()
        confirm(waiting, keeping: kept)
        return kept
    }

    /// Resizes both copies of the terminal, or neither, and returns whether
    /// the size changed. The terminal model checks the size and may refuse
    /// it, so it goes first: a refused size then never reaches the program.
    /// When the program's terminal refuses the size after that, the model
    /// goes back to the old size.
    ///
    /// A program that turned on mode 2048 hears of each new size in an
    /// in-band report. A relaying client whose window changed size sends it
    /// from its own terminal. No terminal reports any other change, so the
    /// session process does, also while a relaying client is attached. The
    /// gate opens only for the resize, which parses no output of the program,
    /// so no query gets a second reply.
    @discardableResult
    private func apply(_ size: SessionSize, requesterReportsSize: Bool = false) throws -> Bool {
        guard size.columns > 0, size.rows > 0, size != summary.size else { return false }
        if !requesterReportsSize { replyGate.close(false) }
        defer { updateReplyGate() }
        try terminal.resize(to: TerminalSize(size))
        do {
            try pseudoTerminal.resize(to: PseudoTerminalSize(size))
        } catch {
            try? terminal.resize(to: TerminalSize(summary.size))
            throw error
        }
        summary.size = size
        return true
    }
}

extension TerminalSize {
    fileprivate init(_ size: SessionSize) {
        self.init(columns: size.columns, rows: size.rows)
    }
}

extension PseudoTerminalSize {
    fileprivate init(_ size: SessionSize) {
        self.init(columns: size.columns, rows: size.rows)
    }
}

extension SessionSummary {
    /// Whether a fact that the sessions list shows differs.
    fileprivate func differsInListedFacts(from other: SessionSummary) -> Bool {
        var (mine, theirs) = (self, other)
        (mine.lastOutputAt, mine.lastInputAt, mine.size) = (nil, nil, theirs.size)
        theirs.lastOutputAt = nil
        theirs.lastInputAt = nil
        return mine != theirs
    }
}

extension SessionExit {
    fileprivate init(_ exit: ProgramExit) {
        switch exit {
        case .exited(let status): self = .exited(status: status)
        case .signaled(let signal): self = .signaled(signal: signal)
        }
    }
}
