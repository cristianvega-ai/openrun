import AgentThreads
import CodexAgent
import Foundation
import SessionProtocol

/// The Codex threads of the registry (decisions of 2026-11-10).
extension ThreadRegistry {
    /// The runner of a thread of any agent, which starts with the first use.
    func running(for identifier: UUID) throws -> any ThreadRunning {
        guard !isStopping else { throw ThreadRunnerError.threadIsClosed }
        guard let record = list.thread(identifier) else { throw ThreadListError.unknownThread(identifier) }
        guard record.agent == .codex else { return try runner(for: identifier) }
        if let runner = codexRunners[identifier] { return runner }
        let runner = CodexThreadRunner(
            record: record, servers: { [weak self] in
                guard let self else { throw ThreadRunnerError.threadIsClosed }
                return try await openCodexServers()
            }, admission: admission, changed: { [weak self] in await self?.codexRunnerChanged($0) })
        codexRunners[identifier] = runner
        return runner
    }

    /// The app-servers of Codex: one for each account, for all threads of
    /// that account. They start with the environment of the login shell.
    func openCodexServers() async throws -> CodexAccountServers {
        guard !isStopping else { throw ThreadRunnerError.threadIsClosed }
        if let codexServers { return codexServers }
        let settings = try await launchSettings()
        guard !isStopping else { throw ThreadRunnerError.threadIsClosed }
        // Another thread can have made them during the wait.
        if let codexServers { return codexServers }
        let servers = CodexAccountServers(launch: CodexServerLaunch(executablePath: settings.codexProgram, environment: settings.environment))
        codexServers = servers
        return servers
    }

    /// A page of the earlier turns of a Codex thread, from Codex itself.
    func codexHistoryPage(of identifier: UUID, cursor: String?) async throws -> CodexHistoryPage {
        guard let runner = try running(for: identifier) as? CodexThreadRunner else { return CodexHistoryPage(events: [], olderCursor: nil) }
        return try await runner.historyPage(cursor: cursor)
    }

    /// Whether an agent of a thread started the process: Claude Code, or
    /// an app-server of Codex, whose commands are its children. Such a
    /// program may not use the threads (decision of 2026-11-10).
    func isStartedByAgent(_ process: pid_t) async -> Bool {
        if await thread(startedProcess: process) != nil { return true }
        guard let identity = await codexServers?.processIdentity() else { return false }
        // A server that starts has no known process yet. Only a program
        // that this process started can be its child, and the app is not one.
        if identity.hasUnidentifiedProcess, ProcessAncestry.ancestor(of: process, among: [getpid()]) != nil { return true }
        return ProcessAncestry.ancestor(of: process, among: Set(identity.identifiers)) != nil
    }

    /// A Codex runner has a new title, state or turn. The record goes to
    /// the file when it changed, and the summary goes to the clients.
    func codexRunnerChanged(_ runner: CodexThreadRunner) async {
        let (record, state, isTurnRunning, waiting, usage, usageReadAt) = await runner.facts
        guard codexRunners[record.identifier] === runner, let kept = list.thread(record.identifier) else { return }
        if kept != record {
            try? list.update(record.identifier) { $0 = record }
            do { try store.save(list) } catch { SessionLog.write("The facts of a thread could not be saved: ", detail: "\(error)") }
        }
        var summary = summary(of: list.thread(record.identifier) ?? record)
        // The app-server of the account is no process of this thread. A turn that runs keeps the session process.
        (summary.state, summary.isProcessRunning, summary.waitingMessageCount) = (state.rawValue, isTurnRunning, waiting)
        summary.usageReadAt = usage == nil ? nil : usageReadAt
        summary.usageWindows = usage?.windows.map {
            ThreadUsageWindow(name: $0.name, lengthInMinutes: $0.lengthInMinutes, usedFraction: $0.usedFraction, resetTime: $0.resetTime, status: $0.status)
        }
        guard summaries[record.identifier] != summary else { return }
        summaries[record.identifier] = summary
        changes?.threadChanged(summary)
    }
}
