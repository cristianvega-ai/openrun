import AgentConversation

/// The stop of a thread: its approvals, its turn, and its commands.
extension CodexAppServer {
    func stop(thread: String) async -> CodexStop {
        guard threads[thread] != nil else { return CodexStop() }
        var stop = CodexStop()
        await endApprovals(of: { $0 == thread })
        // A stop can come before the answer to `turn/start`. Without the
        // wait, the stop found no turn, and the turn ran on.
        let startDeadline = ContinuousClock.now + options.stopTimeLimit
        while threads[thread]?.mapper.turnToStop == nil, (threads[thread]?.startingTurnCount ?? 0) > 0, ContinuousClock.now < startDeadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if let turn = threads[thread]?.mapper.turnToStop {
            let parameters = JSONValue.object(["threadId": .string(thread), "turnId": .string(turn)])
            stop.interruptedTurn = (try? await request("turn/interrupt", parameters)) != nil
            // A command that runs goes on after the interrupt, as a
            // background terminal. It can end only after the end of the turn.
            let deadline = ContinuousClock.now + options.stopTimeLimit
            while threads[thread]?.mapper.turnToStop == turn, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        do {
            let threadParameter: [String: JSONValue] = ["threadId": .string(thread)]
            let terminals = try await request("thread/backgroundTerminals/list", .object(threadParameter))
            for terminal in terminals["data"]?.array ?? [] {
                guard let process = terminal["processId"] else { continue }
                let parameters = threadParameter.merging(["processId": process]) { first, _ in first }
                let result = try await request("thread/backgroundTerminals/terminate", .object(parameters))
                if result["terminated"]?.bool == true { stop.endedCommandCount += 1 } else { stop.commandsMayStillRun = true }
            }
        } catch {
            // The methods are experimental, so a version of Codex can lack
            // them. The turn still stopped.
            stop.commandsMayStillRun = true
        }
        if stop.commandsMayStillRun {
            let text = "OpenRun could not end the commands of the thread, so a command may still run."
            emit([.notice(Notice(level: .warning, text: text))], line: nil, to: thread)
        }
        return stop
    }
}
