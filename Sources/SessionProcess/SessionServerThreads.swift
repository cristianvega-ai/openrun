import AgentConversation
import AgentThreads
import ClaudeCodeAgent
import Foundation
import SessionProtocol

/// The requests for agent threads.
extension SessionServer {
    /// Answers a request for a thread. An attach sends its own answers
    /// and returns nil.
    func answer(threadRequest message: ClientMessage, from client: ClientConnection, peer: PeerProcess, attached: inout (any ThreadRunning)?) async -> ServerMessage? {
        // In version 1 only a program outside every session and every
        // thread may use the threads (decision of 2026-11-10). An agent
        // must not drive another agent without the user.
        guard await registry.place(of: peer) == .outsideEverySession, await !threads.isStartedByAgent(peer.processIdentifier) else {
            return Self.refusal("Only a program outside every session and every thread may use the agent threads.")
        }
        do {
            switch message {
            case .createThread(let agent, let folder, let model, let permissionMode, let name, let account):
                return .threadCreated(try await threads.create(
                    agent: agent, folder: folder, model: model, permissionMode: permissionMode, name: name, account: account))
            case .listThreads:
                return .threadList(await threads.allSummaries)
            case .renameThread(let identifier, let name):
                try await threads.rename(identifier, to: name)
                return .acknowledged
            case .changeThread(let identifier, let model, let permissionMode):
                try await threads.change(identifier, model: model, permissionMode: permissionMode)
                return .acknowledged
            case .openThreadInTerminal(let identifier, let size):
                return try await openInTerminal(identifier, size: size)
            case .returnThreadFromTerminal(let identifier):
                return try await returnFromTerminal(identifier)
            case .closeThread(let identifier):
                try await threads.close(identifier)
                return .acknowledged
            case .sendThreadMessage(let identifier, let text, let images):
                let images = (images ?? []).map { MessageImage(mediaType: $0.mediaType, data: $0.data) }
                return .threadMessageSent(identifier: try await threads.running(for: identifier).send(text: text, images: images))
            case .stopThread(let identifier):
                try await threads.running(for: identifier).stop()
                return .acknowledged
            case .readThreadHistory(let identifier, let before, let cursor):
                let record = try await threads.record(identifier)
                if record.agent == .codex {
                    // Codex gives the turns of a thread itself, by a cursor.
                    let page = try await threads.codexHistoryPage(of: identifier, cursor: cursor)
                    let encoder = JSONEncoder()
                    for event in page.events { client.send(.threadEvent(try encoder.encode(event))) }
                    return .threadHistoryPage(cursor: page.olderCursor)
                }
                let environment = await agents.settings().environment
                // The read waits for the disk, so it runs off this actor.
                let page = try await Task.detached { try ThreadHistory.page(of: record, environment: environment, before: before) }.value
                for event in page.events { client.send(.threadEvent(event)) }
                return .threadHistoryPage(before: page.before)
            case .attachThread(let identifier):
                guard attached == nil else { return Self.refusal("This connection is already attached to a thread.") }
                attached = try await attach(client, toThread: identifier)
                return nil
            default:
                return nil
            }
        } catch {
            return Self.refusal("\(error)")
        }
    }

    /// The permission hook of an agent asks for the user. Only a program
    /// that the agent of a thread started may ask, and its request goes
    /// to that thread. The answer waits for the end of the request. When
    /// the hook leaves, this task is cancelled, and the request ends.
    func answer(permissionRequest payload: Data, from peer: PeerProcess) async -> ServerMessage {
        guard let thread = await threads.thread(startedProcess: peer.processIdentifier), let runner = try? await threads.runner(for: thread),
              let request = try? ClaudeCodePermissionHookRequest(decoding: payload) else {
            return Self.refusal("Only the permission hook of an agent thread may ask for a permission.")
        }
        switch await runner.askPermission(request) {
        case .allow: return .toolPermissionAnswer(allows: true)
        case .deny(let message): return .toolPermissionAnswer(allows: false, message: message)
        }
    }

    /// The answer of the user. Only OpenRun.app, signed and outside every
    /// session and every thread, can give it, as for an approval question.
    /// Any program of the user can reach the socket, so an agent could
    /// else allow its own request (proposal 2 of 2026-11-10).
    func answerPermission(_ request: String, ofThread thread: UUID, allows: Bool, message: String?, from peer: PeerProcess) async -> ServerMessage {
        let isApplication = Self.acceptsAnswerer(
            at: await registry.place(of: peer), meetingRequirement: answererRequirement.isMet(byProgramWithAuditToken: peer.auditToken))
        guard isApplication, await !threads.isStartedByAgent(peer.processIdentifier) else {
            return Self.refusal("Only OpenRun.app answers a permission request.")
        }
        guard let runner = try? await threads.running(for: thread), await runner.answerPermission(request, allows: allows, message: message) else {
            return Self.refusal("That permission request does not wait for an answer.")
        }
        return .acknowledged
    }

    /// Attaches a client to a thread: the summary first, then what the
    /// runner gives, in its order.
    private func attach(_ client: ClientConnection, toThread identifier: UUID) async throws -> any ThreadRunning {
        let runner = try await threads.running(for: identifier)
        guard let summary = await threads.summary(identifier) else { throw ThreadListError.unknownThread(identifier) }
        client.send(.threadAttached(summary))
        await runner.attach(ObjectIdentifier(client)) { delivery in
            switch delivery {
            case .event(let event): client.send(.threadEvent(event))
            case .replayComplete(let hasEarlierEvents): client.send(.threadReplayComplete(hasEarlierEvents: hasEarlierEvents))
            case .closed: client.send(.threadEnded(identifier: identifier))
            }
        }
        return runner
    }
}
