import AgentThreads
import CodexAgent
import Foundation
import Projects
import SessionProtocol

/// The changes of the threads: a new thread, a name, a close, and the
/// facts that a runner reports.
extension ThreadRegistry {
    /// Makes a thread. Its folder must exist, because the agent starts there.
    func create(agent: String, folder: String, model: String?, permissionMode: String?, name: String?, account: String? = nil) throws -> ThreadSummary {
        guard let kind = ThreadAgent(rawValue: agent) else { throw ThreadRequestError.unsupportedAgent(agent) }
        // Without a name, the thread runs under the account of the login shell.
        let chosen = try account.map { name -> ThreadAccount in
            guard let found = accountChoices.account(named: name, of: kind) else { throw ThreadRequestError.unknownAccount }
            return found
        }
        var isFolder: ObjCBool = false
        guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else {
            throw ThreadRequestError.folderDoesNotExist
        }
        // The list of the projects holds the real path of each folder, so
        // the thread keeps the real path too. Foundation leaves `/private` out.
        guard let resolved = realpath(folder, nil) else { throw ThreadRequestError.folderDoesNotExist }
        defer { free(resolved) }
        let realFolder = String(cString: resolved)
        let usual = kind == .codex ? (CodexThreadRunner.configuredModel, CodexSandbox.workspaceWrite.rawValue) : (defaultModel, defaultPermissionMode)
        let mode = try offered(permissionMode ?? usual.1, for: kind)
        let record = ThreadRecord(agent: kind, account: chosen, folder: realFolder, model: model ?? usual.0, permissionMode: mode, name: name)
        let previous = list
        try list.add(record)
        try save(restoring: previous)
        let summary = summary(of: list.thread(record.identifier) ?? record)
        summaries[record.identifier] = summary
        changes?.threadChanged(summary)
        return summary
    }

    /// The mode, when a thread can take it. A wider mode than the one of
    /// the setting changes only in the settings window (proposal 9).
    private func offered(_ mode: String, for agent: ThreadAgent) throws -> String {
        let offered = agent == .codex ? CodexSandbox.allCases.map(\.rawValue) : Self.offeredModes(upTo: defaultPermissionMode)
        guard offered.contains(mode) else { throw ThreadRequestError.permissionModeNotOffered(offered: offered) }
        return mode
    }

    /// Changes the model, the permission mode, or both. The agent takes
    /// them at its next start.
    func change(_ identifier: UUID, model: String?, permissionMode: String?) async throws {
        guard let agent = list.thread(identifier)?.agent else { throw ThreadListError.unknownThread(identifier) }
        let mode = try permissionMode.map { try offered($0, for: agent) }
        let previous = list
        try list.update(identifier) { record in
            (record.model, record.permissionMode) = (model ?? record.model, mode ?? record.permissionMode)
        }
        try save(restoring: previous)
        if let record = list.thread(identifier) {
            await runners[identifier]?.setLaunchFacts(model: record.model, permissionMode: record.permissionMode)
            await codexRunners[identifier]?.setTurnFacts(model: record.model, permissionMode: record.permissionMode)
        }
        publish(identifier)
    }

    func rename(_ identifier: UUID, to name: String?) async throws {
        let previous = list
        try list.update(identifier) { $0.name = name }
        try save(restoring: previous)
        await runners[identifier]?.setName(list.thread(identifier)?.name)
        await codexRunners[identifier]?.setName(list.thread(identifier)?.name)
        publish(identifier)
    }

    /// Ends the process of the thread and removes its record. The history
    /// of the agent stays where the agent keeps it.
    func close(_ identifier: UUID) async throws {
        let previous = list
        try list.remove(identifier)
        try save(restoring: previous)
        summaries[identifier] = nil
        changes?.threadEnded(identifier)
        await runners.removeValue(forKey: identifier)?.close()
        await codexRunners.removeValue(forKey: identifier)?.close()
        if let next = slots.remove(identifier) { await start(next) }
    }

    /// The runner of a thread, which starts with the first use.
    func runner(for identifier: UUID) throws -> ThreadRunner {
        if let runner = runners[identifier] { return runner }
        guard let record = list.thread(identifier) else { throw ThreadListError.unknownThread(identifier) }
        guard record.agent == .claudeCode else { throw ThreadRequestError.onlyForClaudeCode }
        let runner = ThreadRunner(
            record: record, quietTime: quietTime, launchSettings: launchSettings,
            takeProcessSlot: { [weak self] in await self?.takeProcessSlot(for: $0) ?? .granted },
            changed: { [weak self] in await self?.runnerChanged($0) })
        runners[identifier] = runner
        return runner
    }

    /// A runner has a new title, state or process. The record goes to the
    /// file when it changed, and the summary goes to the clients.
    func runnerChanged(_ runner: ThreadRunner) async {
        let ((record, state, process, waiting, holdsProcessSlot), usage) = await (runner.facts, runner.usage)
        guard runners[record.identifier] === runner, let kept = list.thread(record.identifier) else { return }
        // The agent ended, so the thread that waited longest can start its agent.
        if !holdsProcessSlot {
            // A thread with no message, such as after a stop, waits for no slot.
            if waiting == 0 { slots.leaveLine(record.identifier) }
            if let next = slots.release(record.identifier) { await start(next) }
        }
        agentProcesses = agentProcesses.filter { $0.value != record.identifier }
        if let process { agentProcesses[process] = record.identifier }
        let isRunning = process != nil
        if kept != record {
            try? list.update(record.identifier) { $0 = record }
            do { try store.save(list) } catch { SessionLog.write("The facts of a thread could not be saved: ", detail: "\(error)") }
        }
        var summary = summary(of: list.thread(record.identifier) ?? record)
        (summary.state, summary.isProcessRunning, summary.waitingMessageCount) = (state.rawValue, isRunning, waiting)
        summary.usageReadAt = usage?.readAt
        summary.usageWindows = usage?.reading.windows.map {
            ThreadUsageWindow(name: $0.name, lengthInMinutes: $0.lengthInMinutes, usedFraction: $0.usedFraction, resetTime: $0.resetTime, status: $0.status)
        }
        guard summaries[record.identifier] != summary else { return }
        summaries[record.identifier] = summary
        changes?.threadChanged(summary)
    }

    func terminalSession(of thread: UUID) -> UUID? {
        terminals[thread]?.session
    }

    /// Open in Terminal: the thread takes no message until the session ends.
    func openedInTerminal(_ thread: UUID, session: UUID, historyEnd: UInt64) async {
        terminals[thread] = (session, historyEnd)
        await runners[thread]?.setInTerminal()
        publish(thread)
    }

    /// A session ended. When it was the terminal of a thread, the turns
    /// that the user made there come into the events of the thread from
    /// the history of the agent, and the thread takes messages again.
    func sessionEnded(_ session: UUID) async {
        guard let thread = terminals.first(where: { $0.value.session == session })?.key, let terminal = terminals.removeValue(forKey: thread),
              let record = list.thread(thread) else { return }
        if let runner = codexRunners[thread] {
            // Codex keeps the turns itself, and the runner reads them from its history.
            await runner.returnedFromTerminal()
            return publish(thread)
        }
        guard let runner = try? runner(for: thread) else { return }
        let environment = (try? await launchSettings().environment) ?? [:]
        // The read waits for the disk, so it runs off this actor.
        let events = await Task.detached { (try? ThreadHistory.events(of: record, environment: environment, after: terminal.historyEnd)) ?? [] }.value
        await runner.returnedFromTerminal(events: events)
        publish(thread)
    }

    /// A thread in line got a slot. Its agent starts with its next
    /// message. A thread with no message gives the slot to the thread
    /// after it, through `runnerChanged`.
    func start(_ thread: UUID) async {
        guard let runner = runners[thread] else { return }
        await runner.sendNextMessage()
        await runnerChanged(runner)
    }

    /// A runner wants to start its agent. When every slot is taken, an
    /// agent with no work ends to make room. When all of them work, the
    /// thread waits in line (decision of 2026-11-10).
    func takeProcessSlot(for thread: UUID) async -> ProcessSlotAnswer {
        while !slots.take(for: thread), let idle = await idleRunner() {
            await idle.endProcess()
            await runnerChanged(idle)
        }
        return slots.holders.contains(thread) ? .granted : .waits(limit: slots.limit)
    }

    /// The runner whose process has had no work for the longest time.
    private func idleRunner() async -> ThreadRunner? {
        var oldest: (runner: ThreadRunner, since: ContinuousClock.Instant)?
        for thread in slots.holders {
            guard let runner = runners[thread], let since = await runner.idleSince else { continue }
            if oldest.map({ since < $0.since }) ?? true { oldest = (runner, since) }
        }
        return oldest?.runner
    }

    /// Sends the summary of a thread again after a change of its record.
    func publish(_ identifier: UUID) {
        guard let record = list.thread(identifier), var summary = summaries[identifier] else { return }
        let fresh = self.summary(of: record)
        (summary.name, summary.title, summary.projectIdentifier) = (fresh.name, fresh.title, fresh.projectIdentifier)
        (summary.model, summary.permissionMode, summary.models, summary.permissionModes) = (fresh.model, fresh.permissionMode, fresh.models, fresh.permissionModes)
        summary.terminalSession = fresh.terminalSession
        summaries[identifier] = summary
        changes?.threadChanged(summary)
    }

    /// Takes a newer list of the projects, and gives each thread the
    /// project that its folder belongs to now.
    func updateProjects(_ newer: ProjectList) {
        projects = newer
        for record in list.threads { publishIfProjectChanged(record) }
    }

    private func publishIfProjectChanged(_ record: ThreadRecord) {
        let project = projects.project(holding: record.folder)?.identifier
        if summaries[record.identifier]?.projectIdentifier != project { publish(record.identifier) }
    }

    /// Ends the process of every thread, when the session process stops.
    func terminateAll() async {
        for runner in runners.values { await runner.close() }
        for runner in codexRunners.values { await runner.close() }
        await codexServers?.shutDown()
        (runners, codexRunners, codexServers) = ([:], [:], nil)
    }
}
