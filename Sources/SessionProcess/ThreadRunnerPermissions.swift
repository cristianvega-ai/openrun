import AgentConversation
import ClaudeCodeAgent
import Foundation

/// The permission requests of the agent of a thread (decision of
/// 2026-11-10). A request waits for the answer of the user. Every other
/// end refuses it: a stop, the end of the process or of the thread, the
/// time limit, and a hook that left.
extension ThreadRunner {
    /// A request that waits, with the task that ends it at the time limit.
    struct WaitingPermission {
        let continuation: CheckedContinuation<PermissionEnd, Never>
        let timeLimit: Task<Void, Never>
    }

    /// Shows a request of the hook to the clients and waits for its end.
    /// The hook gets an allow only for the answer of the user.
    func askPermission(_ request: ClaudeCodePermissionHookRequest, timeLimit: Duration = ThreadRunner.permissionTimeLimit) async -> ClaudeCodePermissionHookAnswer {
        guard admission.acquire() else { return .deny(message: "The thread is closing.") }
        defer { admission.release() }
        // A request for another conversation is not of this agent.
        guard !isClosed, request.conversationIdentifier == record.conversationIdentifier else {
            return .deny(message: "OpenRun could not ask the user for this request.")
        }
        let identifier = UUID().uuidString.lowercased()
        let call = toolCalls.claim(toolName: request.toolName, input: request.toolInput)
        let end = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let limit = Task { [weak self] in
                    guard (try? await Task.sleep(for: timeLimit)) != nil else { return }
                    await self?.endPermission(identifier, .timedOut)
                }
                waitingPermissions[identifier] = WaitingPermission(continuation: continuation, timeLimit: limit)
                // The wait has its answer path before any client sees the request.
                if Task.isCancelled || isClosed {
                    endPermission(identifier, .cancelled)
                } else {
                    emit(.permissionRequested(request.permissionRequest(identifier: identifier, toolCallIdentifier: call)))
                    Task { await self.changed(self) }
                }
            }
        } onCancel: {
            // The hook left, so nobody takes the answer.
            Task { await self.endPermission(identifier, .cancelled) }
        }
        await changed(self)
        switch end.outcome {
        case .allowed: return .allow
        case .denied: return .deny(message: end.message ?? "The user denied this request.")
        case .timedOut: return .deny(message: "The user did not answer this request in time.")
        case .cancelled: return .deny(message: "The request ended before the user answered it.")
        }
    }

    /// The answer of the user. Returns false when the request does not
    /// wait any more, and then nothing changes.
    func answerPermission(_ identifier: String, allows: Bool, message: String?) -> Bool {
        endPermission(identifier, allows ? .allowed : .denied, message: message)
    }

    /// Ends a request that waits. Only the first end counts.
    @discardableResult
    func endPermission(_ identifier: String, _ outcome: PermissionEnd.Outcome, message: String? = nil) -> Bool {
        guard let waiting = waitingPermissions.removeValue(forKey: identifier) else { return false }
        waiting.timeLimit.cancel()
        let end = PermissionEnd(identifier: identifier, outcome: outcome, message: message)
        emit(.permissionEnded(end))
        waiting.continuation.resume(returning: end)
        return true
    }

    /// Refuses every request that waits, such as at a stop.
    func endPermissions() {
        for identifier in Array(waitingPermissions.keys) { endPermission(identifier, .cancelled) }
    }
}
