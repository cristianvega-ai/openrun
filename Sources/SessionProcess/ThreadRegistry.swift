import AgentThreads
import ClaudeCodeAgent
import CodexAgent
import Dispatch
import Foundation
import Projects
import SessionProtocol

/// The agent threads of the session process: their records, which it
/// keeps in `threads.json`, and the runner of each thread that is in use
/// (decisions of 2026-11-10).
///
/// The registry runs on a serial queue of its own, as the keepers of the
/// projects and the settings do, because a save waits for the disk.
actor ThreadRegistry {
    private let queue = DispatchSerialQueue(label: "ai.cristianvega.openrun.threads")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    let store: ThreadStore
    let changes: SessionChangeFeed?
    let launchSettings: @Sendable () async throws -> AgentLaunchSettings
    var list: ThreadList
    var runners: [UUID: ThreadRunner] = [:]
    /// The runner of each Codex thread that is in use, and the
    /// app-servers of Codex, from the first Codex thread that needs one.
    var codexRunners: [UUID: CodexThreadRunner] = [:]
    var codexServers: CodexAccountServers?
    /// The newest summary of each thread, as the lists of the clients show it.
    var summaries: [UUID: ThreadSummary] = [:]
    var projects: ProjectList
    var projectsVersion = 0
    /// The process of the agent of each thread whose agent runs.
    var agentProcesses: [pid_t: UUID] = [:]
    /// The threads that are open in a terminal (proposal 6): the terminal
    /// session, and the size of the history file when it started.
    var terminals: [UUID: (session: UUID, historyEnd: UInt64)] = [:]
    /// The threads that may run a process now, and the ones that wait.
    var slots: AgentProcessSlots
    let quietTime: Duration
    /// The model and the permission mode of a thread that names none,
    /// from the settings.
    var defaultModel: String
    var defaultPermissionMode: String
    /// The accounts that a new thread can name.
    var accountChoices: ThreadAccountChoices
    private var settingsVersion = 0

    /// Loads the threads. A file that cannot be read never stops the
    /// start: the list starts empty, and the log says so.
    init(
        store: ThreadStore, projects: ProjectList = ProjectList(), changes: SessionChangeFeed? = nil,
        processLimit: Int = AgentProcessSlots.defaultLimit, quietTime: Duration = ThreadRunner.defaultQuietTime,
        defaultModel: String = "opus", defaultPermissionMode: String = "default", accountChoices: ThreadAccountChoices = ThreadAccountChoices(),
        launchSettings: @escaping @Sendable () async throws -> AgentLaunchSettings
    ) {
        (self.store, self.projects, self.changes, self.launchSettings) = (store, projects, changes, launchSettings)
        (self.defaultModel, self.defaultPermissionMode, self.accountChoices) = (defaultModel, defaultPermissionMode, accountChoices)
        (slots, self.quietTime) = (AgentProcessSlots(limit: processLimit), quietTime)
        var loaded = ThreadList()
        do {
            let result = try store.load()
            if let path = result.setAsidePath { SessionLog.write("The file of the threads could not be read and now has the name ", detail: path) }
            loaded = result.list
        } catch {
            SessionLog.write("The threads could not be read, and each change of them fails until they can: ", detail: "\(error)")
        }
        let first = loaded.threads.map { Self.summary(of: $0, in: projects, defaultModel: defaultModel, widestMode: defaultPermissionMode, accounts: accountChoices) }
        list = loaded
        summaries = Dictionary(first.map { ($0.identifier, $0) }, uniquingKeysWith: { summary, _ in summary })
        changes?.replaceThreads(first)
    }

    /// Takes newer settings. They apply to the next thread and to the
    /// next start of an agent, and the agents that run stay.
    func updateSettings(model: String, permissionMode: String, processLimit: Int, accountChoices: ThreadAccountChoices? = nil, version: Int) async {
        guard version > settingsVersion else { return }
        (defaultModel, defaultPermissionMode, settingsVersion) = (model, permissionMode, version)
        // A thread keeps its account, because a resume runs under the same account. It shows the name that the account has now.
        self.accountChoices = accountChoices ?? self.accountChoices
        for thread in slots.setLimit(processLimit) {
            guard settingsVersion == version else { return }
            await start(thread)
        }
        // The setting is the widest mode of every thread, so a thread with a wider one comes down to it.
        for identifier in list.threads.map(\.identifier) {
            guard settingsVersion == version else { return }
            guard let record = list.thread(identifier) else { continue }
            if record.agent != .claudeCode || Self.offeredModes(upTo: permissionMode).contains(record.permissionMode) {
                publish(record.identifier)
            } else {
                try? await change(record.identifier, model: nil, permissionMode: permissionMode)
            }
        }
    }

    /// The permission modes that a thread can take: each mode up to the
    /// one of the setting (proposal 9).
    static func offeredModes(upTo widest: String) -> [String] {
        ClaudeCodePermissionMode.modes(upTo: ClaudeCodePermissionMode(rawValue: widest) ?? .standard).map(\.rawValue)
    }

    /// Every thread, oldest first.
    var allSummaries: [ThreadSummary] {
        list.threads.compactMap { summaries[$0.identifier] }
    }

    func summary(_ identifier: UUID) -> ThreadSummary? {
        summaries[identifier]
    }

    func record(_ identifier: UUID) throws -> ThreadRecord {
        guard let record = list.thread(identifier) else { throw ThreadListError.unknownThread(identifier) }
        return record
    }

    /// The thread whose agent is this process or one of its parents. Such
    /// a program runs for the agent, and not for the user.
    func thread(startedProcess process: pid_t) async -> UUID? {
        if let ancestor = ProcessAncestry.ancestor(of: process, among: Set(agentProcesses.keys)), let thread = agentProcesses[ancestor] {
            return thread
        }
        // A new process can connect before its runner publishes a summary.
        let current = runners
        for (identifier, runner) in current {
            guard let agent = await runner.facts.process else { continue }
            if ProcessAncestry.ancestor(of: process, among: [agent]) != nil { return identifier }
        }
        return nil
    }

    /// Whether a process of an agent runs, so the session process must stay.
    var hasRunningProcess: Bool {
        summaries.values.contains { $0.isProcessRunning }
    }

    func summary(of record: ThreadRecord) -> ThreadSummary {
        var summary = Self.summary(of: record, in: projects, defaultModel: defaultModel, widestMode: defaultPermissionMode, accounts: accountChoices)
        summary.terminalSession = terminals[record.identifier]?.session
        return summary
    }

    /// The summary of a thread that is not in use: idle, with no process.
    /// It holds the choices of the menus of the thread.
    static func summary(
        of record: ThreadRecord, in projects: ProjectList, defaultModel: String, widestMode: String, accounts: ThreadAccountChoices
    ) -> ThreadSummary {
        ThreadSummary(
            identifier: record.identifier, agent: record.agent.rawValue, folder: record.folder, model: record.model,
            permissionMode: record.permissionMode, name: record.name, title: record.title,
            accountName: record.account.map { accounts.currentName(of: $0, of: record.agent) },
            createdAt: record.createdAt, lastActivityAt: record.lastActivityAt,
            projectIdentifier: projects.project(holding: record.folder)?.identifier,
            models: record.agent == .codex
                ? [CodexThreadRunner.configuredModel] + (record.model == CodexThreadRunner.configuredModel ? [] : [record.model])
                : ClaudeCodeModelChoices.choices(with: [defaultModel, record.model]),
            // Codex has two sandboxes, and the wider one is its usual one (decision of 2026-11-10).
            permissionModes: record.agent == .codex ? CodexSandbox.allCases.map(\.rawValue) : offeredModes(upTo: widestMode))
    }

    /// Saves the list, or puts back the list before the change, so the
    /// memory stays equal to the disk.
    func save(restoring previous: ThreadList) throws {
        do {
            try store.save(list)
        } catch {
            list = previous
            SessionLog.write("A change of the threads could not be saved: ", detail: "\(error)")
            throw DataSaveFailure(subject: "the threads", reason: "\(error)")
        }
    }
}
