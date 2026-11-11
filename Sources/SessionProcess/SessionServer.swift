import AgentThreads
import DataStorage
import Foundation
import Projects
import SessionProtocol
import Settings
import TerminalEmulation

/// Accepts clients and answers their requests.
actor SessionServer {
    private let listener: SocketListener
    let registry: SessionRegistry
    private let questions = ApprovalQuestions()
    private let changes = SessionChangeFeed()
    let answererRequirement: AnswererRequirement
    private let projects: ProjectKeeper
    private let settings: SettingKeeper
    let threads: ThreadRegistry
    private var handlers: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var clients: [ObjectIdentifier: ClientConnection] = [:]
    private var acceptTask: Task<Void, Never>?
    /// The last moment with a client or a session, for the idle exit.
    private var lastBusy = ContinuousClock.now
    private var isClosed = false

    /// Starts listening. Throws when another session process already does.
    ///
    /// - Parameter dataFolder: Where the projects and the settings are. Nil
    ///   means the folder of the socket.
    init(
        location: SocketLocation, dataFolder: DataFolder? = nil, answererRequirement: AnswererRequirement = AnswererRequirement(text: nil),
        agentOptions: AgentLaunchProvider.Options = AgentLaunchProvider.Options()
    ) throws {
        self.answererRequirement = answererRequirement
        listener = try SocketListener(location: location)
        // The lock of the socket is taken, so no other session process on
        // this socket reads or writes the files now.
        let dataFolder = dataFolder ?? DataFolder(path: location.folder)
        let projectStore = ProjectStore(dataFolder: dataFolder)
        let loadedProjects = ProjectKeeper.load(from: projectStore)
        projects = ProjectKeeper(store: projectStore, list: loadedProjects, changes: changes)
        let settingStore = SettingsStore(dataFolder: dataFolder)
        let loadedSettings = SettingKeeper.load(from: settingStore)
        settings = SettingKeeper(store: settingStore, values: loadedSettings, changes: changes)
        let agents = AgentLaunchProvider(options: agentOptions, socketPath: location.path)
        threads = ThreadRegistry(store: ThreadStore(dataFolder: dataFolder), projects: loadedProjects, changes: changes) { await agents.settings() }
        // The path of the program is read at the start, because a new build
        // can replace the bundle while the process runs.
        registry = SessionRegistry(
            socketPath: location.path, helperSearchPath: .ofThisProcess(), changes: changes, projects: loadedProjects,
            sessionLimit: loadedSettings.sessionLimit, scrollbackLimit: loadedSettings.scrollbackLimit
        )
    }

    func start() {
        let connections = listener.connections
        acceptTask = Task {
            for await accepted in connections {
                self.accept(accepted.connection, peer: accepted.peer)
            }
        }
    }

    /// Stops accepting, ends every program, and closes every client. The
    /// socket file goes first, so no client can connect to a process that is
    /// about to leave.
    func shutDown() async {
        close()
        await acceptTask?.value
        await registry.terminateAll()
        await threads.terminateAll()
        // Each client gets a short time to take what still waits for it, such
        // as the exit status of its program. See `closeAfterSending`.
        for client in clients.values { client.closeAfterSending() }
        for handler in handlers.values { await handler.value }
    }

    /// Closes the socket when no client and no session was there for
    /// `limit`, and returns whether it did. `beforeClosing` runs first.
    func closeWhenIdle(for limit: Duration, beforeClosing: @Sendable () -> Void) async -> Bool {
        // Clients can arrive while the registry answers, so they are checked
        // again after it. No wait comes between that check and the close.
        guard !isClosed, clients.isEmpty, await registry.isEmpty, await !threads.hasRunningProcess, clients.isEmpty else {
            lastBusy = .now
            return false
        }
        guard ContinuousClock.now - lastBusy >= limit else { return false }
        beforeClosing()
        close()
        return true
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        listener.close()
    }

    // MARK: - Clients

    private func accept(_ connection: MessageConnection, peer: PeerProcess) {
        // The listener can take a connection just before the socket closes.
        // It closes before hello, so its client wakes the next process.
        guard !isClosed else {
            connection.shutdown()
            return
        }
        guard clients.count < ConnectionLimits.maximumClientCount else {
            // The client reads this in place of hello. The reason is an
            // existing one, so protocol version 1 does not change.
            try? connection.send(ServerMessage.failure(SessionFailure(
                reason: .invalidRequest,
                message: "The session process already serves \(ConnectionLimits.maximumClientCount) clients, its limit. Close a client and try again."
            )), stallLimit: .zero)
            connection.shutdown()
            return
        }
        let client = ClientConnection(connection: connection)
        let key = ObjectIdentifier(client)
        clients[key] = client
        let handler = Task {
            await self.serve(client, peer: peer)
            // The place stays taken until the socket is closed and both of the
            // client's threads are done with it. A client that detaches while
            // its last messages still go out counts until then, so clients
            // that come and go fast cannot hold more than the limit of sockets.
            await client.waitUntilClosed()
            self.finish(key)
        }
        handlers[key] = handler
        // A client that leaves is served no further, also while its handler
        // waits, for example for room for its text.
        client.whenClientLeaves { handler.cancel() }
    }

    private func finish(_ key: ObjectIdentifier) {
        clients[key] = nil
        handlers[key] = nil
        lastBusy = .now
    }

    /// Reads messages from one client until it leaves. A connection does one
    /// request after another, and an attach lasts until the client detaches.
    ///
    /// Each message counts against the client's read-ahead until it is handled.
    /// Typed input is handled once it is in the program's backlog.
    ///
    /// When the client detaches or leaves, its input that has not gone to the
    /// program yet is dropped, and its requests that were not handled yet are
    /// dropped too. A client that leaves therefore holds no memory.
    private func serve(_ client: ClientConnection, peer: PeerProcess) async {
        let owner = ObjectIdentifier(client)
        var attachedSession: Session?
        var attachedThread: ThreadRunner?
        var isWatching = false

        messages: for await received in client.messages {
            if Task.isCancelled { break }
            // An answer would mix with the changes, so a watcher only leaves.
            if isWatching, received.message != .detach {
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection receives the session changes and takes no other request.")))
                client.markHandled(received)
                continue
            }
            switch received.message {
            case .hello:
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "Hello was already sent.")))
            case .createSession(let folder, let command, let size, let environment):
                client.send(await create(folder: folder, command: command, size: size, environment: environment))
            case .listSessions:
                client.send(.sessionList(await registry.summaries()))
            case .readScreen(let identifier, let includeScrollback):
                if let refusal = await refusal(of: peer, toward: identifier, .read) {
                    client.send(refusal)
                    break
                }
                let answer = await readScreen(identifier, includeScrollback: includeScrollback)
                if case .screen = answer {
                    // A screen can be larger than the output limit, so it does
                    // not count. The next request waits until it is written,
                    // so a client that asks without reading cannot pile them up.
                    await client.sendAndWait(answer)
                } else {
                    client.send(answer)
                }
            case .sendText(let identifier, let text):
                guard let session = await registry.session(for: identifier) else {
                    client.send(Self.unknownSession(identifier))
                    break
                }
                if let refusal = await refusal(of: peer, toward: identifier, .typing(text)) {
                    client.send(refusal)
                    break
                }
                await session.noteInput(isTyped: false)
                // The answer waits until the text is in the program's backlog,
                // so a client never hears that text arrived when it was lost.
                // The text goes in behind the input that this client typed.
                do {
                    try await session.type(Array(text.utf8))
                    client.send(.acknowledged)
                } catch is CancellationError {
                    break messages
                } catch {
                    client.send(.failure(SessionFailure(
                        reason: .unknownSession,
                        message: "The program of session \(SessionSummary.text(for: identifier)) ended before it took the text."
                    )))
                }
            case .killSession(let identifier):
                guard let session = await registry.session(for: identifier) else {
                    client.send(Self.unknownSession(identifier))
                    break
                }
                if let refusal = await refusal(of: peer, toward: identifier, .kill) {
                    client.send(refusal)
                    break
                }
                guard session === attachedSession else {
                    await session.terminate()
                    client.send(.acknowledged)
                    break
                }
                // The end of the session would close this connection before
                // the answer. So the client leaves the session first, and gets
                // the answer and then the exit status from here.
                await session.detach(client)
                session.withdrawTypedInput(from: owner)
                attachedSession = nil
                let exit = await session.terminate()
                client.send(.acknowledged)
                client.send(.exited(exit), countsTowardOutputLimit: false)
                client.markHandled(received)
                break messages
            case .attach(let identifier, let size, let relaysRawOutput, let receivesSizeChanges, let waitsForOutputRoom):
                guard attachedSession == nil else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection is already attached.")))
                    break
                }
                guard size.columns > 0, size.rows > 0 else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "A session needs at least one column and one row.")))
                    break
                }
                guard let session = await registry.session(for: identifier) else {
                    client.send(Self.unknownSession(identifier))
                    break
                }
                if let refusal = await refusal(of: peer, toward: identifier, .attach) {
                    client.send(refusal)
                    break
                }
                do {
                    let attachment = try await session.attach(
                        client, size: size, relaysRawOutput: relaysRawOutput ?? false,
                        receivesSizeChanges: receivesSizeChanges ?? false, waitsForOutputRoom: waitsForOutputRoom ?? false
                    )
                    switch attachment {
                    case .attached: attachedSession = session
                    case .sessionEnded: client.send(Self.unknownSession(identifier))
                    case .refused(let failure): client.send(.failure(failure))
                    }
                } catch {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "\(error)")))
                }
            case .input(let bytes):
                guard let session = attachedSession else { break }
                await session.noteInput(isTyped: true)
                // The bytes go in behind this client's earlier input, and leave
                // the read-ahead once they are in the backlog. The loop does not
                // wait for them, so the client can still detach while its
                // program reads nothing.
                session.type(Array(bytes), from: owner) { client.markHandled(received) }
                continue
            case .resize(let size, let confirmation):
                if confirmation == true && (attachedSession == nil || size.columns == 0 || size.rows == 0) {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "A resize needs an attached session and a nonzero size.")))
                    client.markHandled(received)
                    break messages
                }
                do {
                    try await attachedSession?.resize(to: size, from: client, confirmsResize: confirmation == true)
                } catch {
                    if confirmation == true {
                        client.send(.failure(SessionFailure(reason: .invalidRequest, message: "The session could not change size: \(error)")))
                        client.markHandled(received)
                        break messages
                    }
                }
            case .detach:
                client.markHandled(received)
                break messages
            case .receiveApprovalQuestions:
                // The app, signed and outside every session, is the only
                // program that can answer (ApprovalQuestion.tla).
                guard Self.acceptsAnswerer(at: await registry.place(of: peer), meetingRequirement: answererRequirement.isMet(byProgramWithAuditToken: peer.auditToken)) else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "Only OpenRun.app receives approval questions.")))
                    break
                }
                client.send(.acknowledged)
                await questions.addAnswerer(owner) { client.send($0) }
            case .answerApprovalQuestion(let identifier, let allows):
                await questions.answer(identifier, allows: allows, from: owner)
            case .receiveSessionChanges(let includesThreads):
                guard attachedSession == nil else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection is attached.")))
                    break
                }
                isWatching = true
                changes.addWatcher(owner, includesThreads: includesThreads == true) { client.send($0) }
            case .renameSession(let identifier, let name):
                let name = name?.isEmpty == true ? nil : name
                // A list shows the name on one line.
                // Scalars, because the equality of strings ignores some changes.
                guard name.map({ SessionSummary.boundedText($0).unicodeScalars.elementsEqual($0.unicodeScalars) }) ?? true else {
                    let rule = "no control character, no mark of text direction, no line separator, and at most \(SessionSummary.textLimit) characters"
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "A name holds \(rule).")))
                    break
                }
                client.send(await changeOwn(identifier, for: peer, verb: "rename") { $0.name = name })
            case .raiseSessionAlert(let identifier, let text):
                client.send(await changeOwn(identifier, for: peer, verb: "alert") { $0.alert = SessionAlert(text: text, raisedAt: Date(), source: .notifyCommand) })
            case .clearSessionAlert(let identifier):
                client.send(await changeOwn(identifier, for: peer, verb: "clear the alert of") { $0.alert = nil })
            case .listProjects:
                client.send(.projectList(ProjectKeeper.summaries(of: await projects.list)))
            case .addProject(let folder, let name, let currentFolder):
                client.send(await changeProjects {
                    let added = try await self.projects.add(folder: folder, name: name, currentFolder: currentFolder)
                    return (.projectAdded(ProjectKeeper.summary(of: added.project)), added.list, added.version)
                })
            case .removeProject(let identifier):
                client.send(await changeProjects {
                    let changed = try await self.projects.remove(identifier: identifier)
                    return (.acknowledged, changed.list, changed.version)
                })
            case .renameProject(let identifier, let name):
                client.send(await changeProjects {
                    let changed = try await self.projects.rename(identifier: identifier, to: name)
                    return (.acknowledged, changed.list, changed.version)
                })
            case .moveProject(let identifier, let place):
                client.send(await changeProjects {
                    let changed = try await self.projects.move(identifier: identifier, to: place)
                    return (.acknowledged, changed.list, changed.version)
                })
            case .listSettings:
                client.send(.settingList(SettingKeeper.summaries(of: await settings.values)))
            case .changeSetting(let name, let text):
                client.send(await changeSetting(name, to: text, for: peer))
            case .createThread, .listThreads, .renameThread, .closeThread, .attachThread, .sendThreadMessage, .stopThread:
                guard attachedSession == nil else {
                    client.send(Self.refusal("This connection is attached to a session."))
                    break
                }
                if let answer = await answer(threadRequest: received.message, from: client, peer: peer, attached: &attachedThread) { client.send(answer) }
            case .requestToolPermission(let request):
                client.send(await answer(permissionRequest: request, from: peer))
            case .answerToolPermission(let thread, let request, let allows, let message):
                client.send(await answerPermission(request, ofThread: thread, allows: allows, message: message, from: peer))
            }
            client.markHandled(received)
        }

        await attachedThread?.detach(owner)
        if let attachedSession {
            await attachedSession.detach(client)
            attachedSession.withdrawTypedInput(from: owner)
        }
        await questions.removeAnswerer(owner)
        changes.removeWatcher(owner)
        client.closeAfterSending()
    }

    private func create(folder: String, command: [String]?, size: SessionSize, environment: [String: String]) async -> ServerMessage {
        guard size.columns > 0, size.rows > 0 else {
            return .failure(SessionFailure(reason: .invalidRequest, message: "A session needs at least one column and one row."))
        }
        // No command means the login shell. An empty one names no program, so
        // it is a mistake of the client, not a request for the shell.
        if let command, command.isEmpty {
            return .failure(SessionFailure(reason: .invalidRequest, message: "The command is empty. Name a program, or send no command to start the login shell."))
        }
        do {
            let summary = try await registry.create(folder: folder, command: command, size: size, environment: environment)
            SessionLog.write("Started session \(summary.identifierText) in ", detail: folder)
            return .sessionCreated(summary)
        } catch {
            return .failure(SessionFailure(reason: .launchFailed, message: "\(error)"))
        }
    }

    private func readScreen(_ identifier: UUID, includeScrollback: Bool) async -> ServerMessage {
        guard let session = await registry.session(for: identifier) else { return Self.unknownSession(identifier) }
        do {
            return .screen(text: try await session.screenText(includeScrollback: includeScrollback))
        } catch {
            return .failure(SessionFailure(reason: .invalidRequest, message: "\(error)"))
        }
    }

    /// What a caller in one session wants to do to another one.
    /// Nil when the caller may do a request on the target session: the
    /// caller may act on it freely, or the user allowed it. Otherwise the
    /// refusal. While the question waits, this client sends no other request
    /// (decisions of 2026-10-15 and 2026-11-10, ApprovalQuestion.tla).
    private func refusal(of peer: PeerProcess, toward target: UUID, _ request: ApprovalQuestion.Request) async -> ServerMessage? {
        let place = await registry.place(of: peer)
        guard !place.mayAct(on: target) else { return nil }
        let verb = switch request {
        case .type: "type into"
        case .read: "read"
        case .attach: "attach to"
        case .kill: "kill"
        }
        let targetText = SessionSummary.text(for: target)
        guard case .session(let own) = place, let asking = await registry.session(for: own),
              let targetSession = await registry.session(for: target) else {
            return Self.refusal("The program that asked to \(verb) session \(targetText) runs in no session that the session process can name, such as one that has ended. Such a request needs the user's approval, and it is refused.")
        }
        let start = "A program in session \(SessionSummary.text(for: own)) asked to \(verb) session \(targetText)"
        let question = ApprovalQuestion(identifier: UUID(), askingSession: await asking.summary, targetSession: await targetSession.summary, request: request)
        switch await questions.ask(question) {
        case .allowed: return nil
        case .denied: return Self.refusal("\(start), and the user did not allow it.")
        case .timedOut: return Self.refusal("\(start), and the user did not answer in time.")
        case .noAnswerer: return Self.refusal("\(start). This needs the user's approval, and no signed OpenRun app is open to ask.")
        case .withdrawn: return Self.refusal("\(start), and then it left.")
        case .anotherQuestionWaits: return Self.refusal("\(start) while another question of that session waits for the user.")
        }
    }

    /// Changes a fact that a client gives. A program in a session may change
    /// only its own session, and no question is asked, because a name or an
    /// alert neither types nor reads (decision of 2026-11-10).
    private func changeOwn(_ identifier: UUID, for peer: PeerProcess, verb: String, _ change: @escaping @Sendable (inout SessionSummary) -> Void) async -> ServerMessage {
        guard let session = await registry.session(for: identifier) else { return Self.unknownSession(identifier) }
        guard await registry.place(of: peer).mayAct(on: identifier) else {
            let target = SessionSummary.text(for: identifier)
            return Self.refusal("Only a program outside every session, or a program in the session itself, may \(verb) session \(target).")
        }
        return await session.update(change) ? .acknowledged : Self.unknownSession(identifier)
    }

    /// Runs a change of the projects and returns the answer, or the reason
    /// why nothing changed. Any client may change the projects, because a
    /// change types into no session and reads none (decision of 2026-11-10).
    private func changeProjects(_ change: () async throws -> (answer: ServerMessage, list: ProjectList, version: Int)) async -> ServerMessage {
        do {
            let (answer, list, version) = try await change()
            await registry.updateProjects(list, version: version)
            await threads.updateProjects(list)
            return answer
        } catch {
            return Self.refusal("\(error)")
        }
    }

    /// Changes a setting. Any client may change a setting that is not
    /// protected. A protected one changes only for OpenRun.app: the program
    /// that also may answer the questions (decision of 2026-10-27).
    private func changeSetting(_ name: String, to text: String, for peer: PeerProcess) async -> ServerMessage {
        var requester = SettingRequester.otherClient
        // The check of the signature costs a call of the system, so only a
        // protected setting makes it.
        if SettingName(rawValue: name)?.isProtected == true,
           Self.acceptsAnswerer(at: await registry.place(of: peer), meetingRequirement: answererRequirement.isMet(byProgramWithAuditToken: peer.auditToken)) {
            requester = .application
        }
        do {
            let (values, version) = try await settings.change(name: name, to: text, requestedBy: requester)
            await registry.updateLimits(sessionLimit: values.sessionLimit, scrollbackLimit: values.scrollbackLimit, version: version)
            return .acknowledged
        } catch {
            return Self.refusal("\(error)")
        }
    }

    /// Only the signed app outside every session receives questions. An app
    /// that a program in a session started counts as that program.
    static func acceptsAnswerer(at place: CallerPlace, meetingRequirement: Bool) -> Bool {
        place == .outsideEverySession && meetingRequirement
    }

    /// The reason is an existing one, so protocol version 1 does not change.
    static func refusal(_ message: String) -> ServerMessage {
        .failure(SessionFailure(reason: .invalidRequest, message: message))
    }

    private static func unknownSession(_ identifier: UUID) -> ServerMessage {
        .failure(SessionFailure(reason: .unknownSession, message: "No session has the identifier \(SessionSummary.text(for: identifier))."))
    }

    /// Logs a message that can hold a path or an error text, so all of it
    /// is private in the unified log. See `SessionLog`.
    static func log(_ message: String) {
        SessionLog.write("", detail: message)
    }
}
