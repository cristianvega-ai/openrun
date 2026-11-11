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
        guard !approvals.values.contains(where: { $0.request == request }) else {
            // A second request with the identifier of one that waits would
            // take its place, and the first could then never end.
            await sendDecision("decline", to: request)
            let text = "Codex sent a second request with the identifier \(request) while the first waited, so OpenRun declined it."
            return emit([.notice(Notice(level: .warning, text: text))], line: line, to: thread)
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
        emit([.permissionRequested(approval.permissionRequest(identifier: identifier, startedItem: started))], line: line, to: thread)
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
        emit([.permissionEnded(end)], line: nil, to: approval.thread)
    }

    /// Shows a request again when the start of its item comes after it,
    /// so that the chat gets the diff of a file change.
    func showApprovals(of item: String, line: SourceLine) async {
        for (identifier, approval) in approvals where approval.item == item {
            let request = approval.permissionRequest(identifier: identifier, startedItem: threads[approval.thread]?.mapper.startedItem(item))
            emit([.permissionRequested(request)], line: line, to: approval.thread)
        }
    }

    /// Codex withdrew a request, such as after an interrupt. No answer
    /// goes, and the request ends without one.
    func approvalResolved(_ parameters: JSONValue, thread: String) async {
        guard let request = parameters["requestId"] else { return }
        guard let identifier = approvals.first(where: { $0.value.thread == thread && $0.value.request.isNamed(by: request) })?.key else { return }
        await endApproval(identifier, decision: nil, outcome: .cancelled, reason: .other, message: "Codex withdrew the request.")
    }

    /// Ends the approvals of the threads that `isIncluded` names. While the
    /// app-server runs, each one is declined. After its end, none can be.
    func endApprovals(of isIncluded: (String) -> Bool) async {
        let message = hasEnded ? "The Codex app-server ended, so the request was declined." : "OpenRun declined the request."
        for (identifier, approval) in approvals where isIncluded(approval.thread) {
            await endApproval(identifier, decision: hasEnded ? nil : "decline", outcome: .cancelled, reason: .other, message: message)
        }
    }

    func sendDecision(_ decision: String, to request: CodexRequestIdentifier) async {
        guard let line = try? CodexOutgoingLine.response(to: request, result: .object(["decision": .string(decision)])) else { return }
        await connection.send(line)
    }
}
