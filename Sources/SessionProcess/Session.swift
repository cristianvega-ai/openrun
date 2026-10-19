import Foundation
import PseudoTerminal
import SessionProtocol
import Synchronization
import TerminalEmulation

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
    private let replyGate: ReplyGate
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
    /// - Parameter installReplyHandler: Installs the handler on the terminal.
    ///   Tests replace it to make the installation fail.
    init(
        summary: SessionSummary,
        launch: ProgramLaunch,
        onFinish: @escaping @Sendable (UUID) async -> Void,
        installReplyHandler: (Terminal, @escaping TerminalReplyHandler) throws -> Void = { try $0.setReplyHandler($1) }
    ) throws {
        self.summary = summary
        self.onFinish = onFinish
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
    /// client is refused before `attached`, and the session keeps its size.
    /// The other clients that asked hear of a new size.
    ///
    /// A client that relays raw output has a real terminal that answers queries.
    /// While one is attached, the session process sends no replies. Two such
    /// clients answer the same query twice. That limit is accepted for now.
    func attach(_ client: ClientConnection, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool) throws -> Attachment {
        guard !isFinished else { return .sessionEnded }
        let previousSize = summary.size
        defer { if summary.size != previousSize { announceSize(changedBy: client) } }
        try apply(size)
        guard let snapshot = try TerminalSnapshot(capturing: terminal, byteLimit: MessageFrame.maximumPayloadLength) else {
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
        client.send(.snapshot(Data(snapshot.bytes)), countsTowardOutputLimit: false)
        clients[ObjectIdentifier(client)] = client
        if relaysRawOutput { relayingClients.insert(ObjectIdentifier(client)) }
        if receivesSizeChanges { clientsThatReceiveSizeChanges.insert(ObjectIdentifier(client)) }
        updateReplyGate()
        return .attached
    }

    func detach(_ client: ClientConnection) {
        clients[ObjectIdentifier(client)] = nil
        relayingClients.remove(ObjectIdentifier(client))
        clientsThatReceiveSizeChanges.remove(ObjectIdentifier(client))
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

    /// Resizes the program's terminal and the session's copy of it. The last
    /// client to resize wins, and the other clients that asked hear of it.
    func resize(to size: SessionSize, from requester: ClientConnection) throws {
        let reportsItself = relayingClients.contains(ObjectIdentifier(requester))
        if try apply(size, requesterReportsSize: reportsItself) { announceSize(changedBy: requester) }
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
        await pseudoTerminal.terminate()
        await runTask?.value
        if let programExit { return programExit }
        return SessionExit(await pseudoTerminal.waitForExit())
    }

    // MARK: - Private

    private func run() async {
        for await bytes in pseudoTerminal.output {
            // Output that arrives while the session ends needs no parsing. The
            // screen is about to disappear, and parsing could delay a shutdown.
            if !isEnding {
                terminal.write(bytes)
                let message = ServerMessage.output(Data(bytes))
                for client in clients.values { client.send(message) }
            }
            pseudoTerminal.markOutputConsumed(bytes.count)
            // A program that asks questions and never reads the answers waits
            // here, in its own output, instead of growing the input backlog.
            await pseudoTerminal.waitForAnswerRoom()
            // A steady stream never suspends this loop, and the actor would
            // serve nobody else. Yielding lets attach, read and kill run.
            await Task.yield()
        }
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
        updateReplyGate()
        await onFinish(summary.identifier)
    }

    private func updateReplyGate() {
        replyGate.close(!relayingClients.isEmpty)
    }

    /// A client that draws the screen itself must lay out the output that
    /// follows for the new size. The message goes out before that output.
    /// The requester knows its own size and does not get it.
    private func announceSize(changedBy requester: ClientConnection) {
        for (key, client) in clients where key != ObjectIdentifier(requester) && clientsThatReceiveSizeChanges.contains(key) {
            client.send(.sizeChanged(summary.size))
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
    /// gate opens only for the resize, which parses no output, so no query
    /// gets a second reply.
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
