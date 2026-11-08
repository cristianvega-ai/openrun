import Foundation
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
    /// The line limit of the scrollback that every session keeps.
    static let scrollbackLimit = 10_000

    private(set) var summary: SessionSummary
    private let pseudoTerminal: PseudoTerminal
    private let terminal: Terminal
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
    /// milliseconds, so the limit only ends a wait for an answer that has
    /// another form.
    private let answerTimeLimit: Duration
    private var isFinished = false
    private var isEnding = false
    private var programExit: SessionExit?
    private var runTask: Task<Void, Never>?
    private let onFinish: @Sendable (UUID) async -> Void

    /// Creates the terminal, then starts the program.
    ///
    /// The program starts last, so nothing can fail after it runs. A failure
    /// before it leaves no program running without a session.
    ///
    /// - Parameters:
    ///   - answerTimeLimit: How long a new size waits for a line editor.
    ///   - installReplyHandler: Installs the handler on the terminal. Tests
    ///     replace it to make the installation fail, or to fix the scheme.
    init(
        summary: SessionSummary,
        launch: ProgramLaunch,
        onFinish: @escaping @Sendable (UUID) async -> Void,
        answerTimeLimit: Duration = .milliseconds(500),
        installReplyHandler: (Terminal, @escaping TerminalReplyHandler) throws -> Void = { try Session.installReplies(on: $0, handler: $1) }
    ) throws {
        self.summary = summary
        self.onFinish = onFinish
        self.answerTimeLimit = answerTimeLimit
        let gate = ReplyGate()
        replyGate = gate
        terminal = try Terminal(size: TerminalSize(summary.size), scrollbackLimit: Self.scrollbackLimit)
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
        runTask = Task { await self.run() }
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
    /// the attach, without the answer, because the attach comes later.
    ///
    /// A client that relays raw output has a real terminal that answers queries.
    /// While one is attached, the session process sends no replies. Two such
    /// clients answer the same query twice. That limit is accepted for now.
    func attach(_ client: ClientConnection, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool, waitsForOutputRoom: Bool) throws -> Attachment {
        guard !isFinished else { return .sessionEnded }
        while lineEditorWait.isWaiting { finishWait(keepsCursorAtLineStart: false) }
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
                if let end = lineEditorWait.end(in: rest) {
                    show(rest[..<end.index])
                    finishWait(keepsCursorAtLineStart: end.erasedLines)
                    // A new wait can start here. The rest of these bytes came
                    // before its new size, so they cannot hold its answer.
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
        await onFinish(summary.identifier)
    }

    /// Parses program output and sends it to every client.
    private func show(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty else { return }
        terminal.write(bytes)
        let message = ServerMessage.output(Data(bytes))
        for client in clients.values { client.send(message) }
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
    private func announceSize(changedBy requester: ObjectIdentifier?, keepsCursorAtLineStart: Bool = false) {
        for (key, client) in clients where key != requester && clientsThatReceiveSizeChanges.contains(key) {
            client.send(sizeChanged(keepsCursorAtLineStart: keepsCursorAtLineStart))
        }
    }

    private func confirm(_ request: LineEditorWait.Request, keepsCursorAtLineStart: Bool = false) {
        guard request.confirms, let requester = request.requester else { return }
        clients[requester]?.send(sizeChanged(keepsCursorAtLineStart: keepsCursorAtLineStart))
    }

    private func sizeChanged(keepsCursorAtLineStart: Bool) -> ServerMessage {
        .sizeChanged(summary.size, keepsCursorAtLineStart: keepsCursorAtLineStart ? true : nil)
    }

    /// The line editor that waits at the cursor. zsh and bash turn on
    /// bracketed paste only while they edit a command line, and the program
    /// that reads the keys must be such a shell itself: an agent or another
    /// program in the foreground draws its own way.
    private func waitingLineEditor() -> LineEditor? {
        guard !terminal.isAlternateScreenActive, terminal.isModeEnabled(.bracketedPaste),
              let program = pseudoTerminal.foregroundProgram
        else { return nil }
        return InteractiveShell.lineEditor(of: program)
    }

    /// Applies a resize at once, or starts to wait for a line editor when
    /// the width changes under one. New rows alone reflow no text, so the
    /// editor's count of rows stays right.
    private func change(by request: LineEditorWait.Request) throws {
        let size = request.size
        if size.columns > 0, size.rows > 0, size.columns != summary.size.columns, let editor = waitingLineEditor() {
            try Terminal.validate(TerminalSize(size))
            try pseudoTerminal.resize(to: PseudoTerminalSize(size))
            let number = lineEditorWait.start(request, editor: editor, earlierByteCount: 0)
            Task { [weak self, answerTimeLimit] in
                try? await Task.sleep(for: answerTimeLimit)
                await self?.answerTimeLimitPassed(number)
            }
            return
        }
        if try apply(size, requesterReportsSize: request.reportsItself) { announceSize(changedBy: request.requester) }
        confirm(request)
        sendOwedSizes()
    }

    /// Tells the clients whose confirmed resize a newer one replaced.
    private func sendOwedSizes(keepsCursorAtLineStart: Bool = false) {
        for client in lineEditorWait.takeClientsOwedTheSize() {
            clients[client]?.send(sizeChanged(keepsCursorAtLineStart: keepsCursorAtLineStart))
        }
    }

    private func answerTimeLimitPassed(_ number: Int) {
        guard !isFinished, lineEditorWait.isWaiting, lineEditorWait.number == number else { return }
        finishWait(keepsCursorAtLineStart: false)
    }

    /// Gives the terminal model the size that the program has, and tells the
    /// clients, in order with the output. Then the resize that came during
    /// the wait applies.
    ///
    /// - Parameter keepsCursorAtLineStart: True where the shell has erased its
    ///   lines. The model and the clients then keep the cursor's row apart
    ///   from the output above it (see `Terminal.resize`).
    private func finishWait(keepsCursorAtLineStart: Bool) {
        guard let (finished, next) = lineEditorWait.finish() else { return }
        if !finished.reportsItself { replyGate.close(false) }
        do {
            try terminal.resize(to: TerminalSize(finished.size), keepingCursorAtLineStart: keepsCursorAtLineStart)
            summary.size = finished.size
            announceSize(changedBy: finished.requester, keepsCursorAtLineStart: keepsCursorAtLineStart)
        } catch {
            // The size was checked, so only a lack of memory gets here. The
            // program goes back to the size of the model.
            try? pseudoTerminal.resize(to: PseudoTerminalSize(summary.size))
        }
        updateReplyGate()
        confirm(finished, keepsCursorAtLineStart: keepsCursorAtLineStart)
        guard let next else { return sendOwedSizes(keepsCursorAtLineStart: keepsCursorAtLineStart) }
        do {
            try change(by: next)
        } catch {
            // The size of `next` was checked when it came. When the program's
            // terminal refuses it now, the requester hears of the size in use.
            confirm(next)
            sendOwedSizes()
        }
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

extension SessionExit {
    fileprivate init(_ exit: ProgramExit) {
        switch exit {
        case .exited(let status): self = .exited(status: status)
        case .signaled(let signal): self = .signaled(signal: signal)
        }
    }
}
