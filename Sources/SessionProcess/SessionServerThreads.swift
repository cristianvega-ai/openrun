import AgentConversation
import AgentThreads
import Foundation
import SessionProtocol

/// The requests for agent threads.
extension SessionServer {
    /// Answers a request for a thread. An attach sends its own answers
    /// and returns nil.
    func answer(threadRequest message: ClientMessage, from client: ClientConnection, peer: PeerProcess, attached: inout ThreadRunner?) async -> ServerMessage? {
        // In version 1 only a program outside every session and every
        // thread may use the threads (decision of 2026-11-10). An agent
        // must not drive another agent without the user.
        guard await registry.place(of: peer) == .outsideEverySession, await threads.thread(startedProcess: peer.processIdentifier) == nil else {
            return Self.refusal("Only a program outside every session and every thread may use the agent threads.")
        }
        do {
            switch message {
            case .createThread(let agent, let folder, let model, let permissionMode, let name):
                return .threadCreated(try await threads.create(agent: agent, folder: folder, model: model, permissionMode: permissionMode, name: name))
            case .listThreads:
                return .threadList(await threads.allSummaries)
            case .renameThread(let identifier, let name):
                try await threads.rename(identifier, to: name)
                return .acknowledged
            case .closeThread(let identifier):
                try await threads.close(identifier)
                return .acknowledged
            case .sendThreadMessage(let identifier, let text, let images):
                let images = (images ?? []).map { MessageImage(mediaType: $0.mediaType, data: $0.data) }
                return .threadMessageSent(identifier: try await threads.runner(for: identifier).send(text: text, images: images))
            case .stopThread(let identifier):
                try await threads.runner(for: identifier).stop()
                return .acknowledged
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

    /// Attaches a client to a thread: the summary first, then what the
    /// runner gives, in its order.
    private func attach(_ client: ClientConnection, toThread identifier: UUID) async throws -> ThreadRunner {
        let runner = try await threads.runner(for: identifier)
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
