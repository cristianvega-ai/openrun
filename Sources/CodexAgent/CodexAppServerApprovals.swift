import AgentConversation

/// The approvals: a request of Codex becomes a permission request of the
/// thread, and only the user's answer accepts it.
extension CodexAppServer {
    func approvalRequested(_ request: CodexRequestIdentifier, method: String, parameters: JSONValue, line: SourceLine) async {
        guard let thread = Self.threadIdentifier(of: parameters), threads[thread] != nil else {
            // No open thread can show the request, so OpenRun declines it.
            await sendDecision("decline", to: request)
            return
        }
        let item = parameters["itemId"]?.string ?? ""
        let identifier = "\(item)/\(request)"
        let limit = options.approvalTimeLimit
        let timer = Task { [weak self] in
            guard (try? await Task.sleep(for: limit)) != nil else { return }
            await self?.endApproval(identifier, decision: "decline", outcome: .timedOut, reason: .unanswered,
                                    message: "No one answered in time, so OpenRun declined the request.")
        }
        let approval = CodexApproval(thread: thread, request: request, item: item, method: method, parameters: parameters, timer: timer)
        approvals[identifier] = approval
        let started = threads[thread]?.mapper.startedItem(item)
        await threads[thread]?.send([.permissionRequested(approval.permissionRequest(identifier: identifier, startedItem: started))], line: line)
    }

    func answerPermission(_ identifier: String, answer: CodexPermissionAnswer, thread: String) async -> Bool {
        guard approvals[identifier]?.thread == thread else { return false }
        await endApproval(identifier, decision: answer.decision, outcome: answer == .allow ? .allowed : .denied, reason: .user, message: nil)
        return true
    }

    /// Ends an approval. With a decision, the answer goes to Codex. Without
    /// one, no answer goes, as after the end of the app-server.
    func endApproval(
        _ identifier: String, decision: String?, outcome: PermissionEnd.Outcome, reason: ToolCallRefusal.Reason, message: String?
    ) async {
        guard let approval = approvals.removeValue(forKey: identifier) else { return }
        approval.timer.cancel()
        if let decision { await sendDecision(decision, to: approval.request) }
        if decision == "decline" { threads[approval.thread]?.mapper.noteDecline(of: approval.item, reason: reason) }
        let end = PermissionEnd(identifier: identifier, outcome: outcome, message: message)
        await threads[approval.thread]?.send([.permissionEnded(end)], line: nil)
    }

    /// Codex withdrew a request, such as after an interrupt. No answer
    /// goes, and the request ends without one.
    func approvalResolved(_ parameters: JSONValue, thread: String) async {
        guard let request = parameters["requestId"].flatMap(CodexRequestIdentifier.init) else { return }
        guard let identifier = approvals.first(where: { $0.value.thread == thread && $0.value.request == request })?.key else { return }
        await endApproval(identifier, decision: nil, outcome: .cancelled, reason: .other, message: "Codex withdrew the request.")
    }

    func sendDecision(_ decision: String, to request: CodexRequestIdentifier) async {
        guard let line = try? CodexOutgoingLine.response(to: request, result: .object(["decision": .string(decision)])) else { return }
        await connection.send(line)
    }
}
