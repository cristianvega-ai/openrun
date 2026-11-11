import AgentThreads
import ClaudeCodeAgent
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
    /// The newest summary of each thread, as the lists of the clients show it.
    var summaries: [UUID: ThreadSummary] = [:]
    var projects: ProjectList
    /// The process of the agent of each thread whose agent runs.
    var agentProcesses: [pid_t: UUID] = [:]
    /// The threads that may run a process now, and the ones that wait.
    var slots: AgentProcessSlots
    let quietTime: Duration
    /// The model and the permission mode of a thread that names none,
    /// from the settings.
    var defaultModel: String
    var defaultPermissionMode: String
    private var settingsVersion = 0

    /// Loads the threads. A file that cannot be read never stops the
    /// start: the list starts empty, and the log says so.
    init(
        store: ThreadStore, projects: ProjectList = ProjectList(), changes: SessionChangeFeed? = nil,
        processLimit: Int = AgentProcessSlots.defaultLimit, quietTime: Duration = ThreadRunner.defaultQuietTime,
        defaultModel: String = "opus", defaultPermissionMode: String = "default",
        launchSettings: @escaping @Sendable () async throws -> AgentLaunchSettings
    ) {
        (self.store, self.projects, self.changes, self.launchSettings) = (store, projects, changes, launchSettings)
        (self.defaultModel, self.defaultPermissionMode) = (defaultModel, defaultPermissionMode)
        (slots, self.quietTime) = (AgentProcessSlots(limit: processLimit), quietTime)
        var loaded = ThreadList()
        do {
            let result = try store.load()
            if let path = result.setAsidePath { SessionLog.write("The file of the threads could not be read and now has the name ", detail: path) }
            loaded = result.list
        } catch {
            SessionLog.write("The threads could not be read, and each change of them fails until they can: ", detail: "\(error)")
        }
        let first = loaded.threads.map { Self.summary(of: $0, in: projects, defaultModel: defaultModel, widestMode: defaultPermissionMode) }
        list = loaded
        summaries = Dictionary(first.map { ($0.identifier, $0) }, uniquingKeysWith: { summary, _ in summary })
        changes?.replaceThreads(first)
    }

    /// Takes newer settings. They apply to the next thread and to the
    /// next start of an agent, and the agents that run stay.
    func updateSettings(model: String, permissionMode: String, processLimit: Int, version: Int) async {
        guard version > settingsVersion else { return }
        (defaultModel, defaultPermissionMode, settingsVersion) = (model, permissionMode, version)
        for thread in slots.setLimit(processLimit) { await runners[thread]?.sendNextMessage() }
        // The menus of each thread offer the modes up to the one of the setting.
        for record in list.threads { publish(record.identifier) }
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

    /// The thread whose agent is this process or one of its parents. Such
    /// a program runs for the agent, and not for the user.
    func thread(startedProcess process: pid_t) -> UUID? {
        guard !agentProcesses.isEmpty else { return nil }
        return ProcessAncestry.ancestor(of: process, among: Set(agentProcesses.keys)).flatMap { agentProcesses[$0] }
    }

    /// Whether a process of an agent runs, so the session process must stay.
    var hasRunningProcess: Bool {
        summaries.values.contains { $0.isProcessRunning }
    }

    func summary(of record: ThreadRecord) -> ThreadSummary {
        Self.summary(of: record, in: projects, defaultModel: defaultModel, widestMode: defaultPermissionMode)
    }

    /// The summary of a thread that is not in use: idle, with no process.
    /// It holds the choices of the menus of the thread.
    static func summary(of record: ThreadRecord, in projects: ProjectList, defaultModel: String, widestMode: String) -> ThreadSummary {
        ThreadSummary(
            identifier: record.identifier, agent: record.agent.rawValue, folder: record.folder, model: record.model,
            permissionMode: record.permissionMode, name: record.name, title: record.title, accountName: record.account?.name,
            createdAt: record.createdAt, lastActivityAt: record.lastActivityAt,
            projectIdentifier: projects.project(holding: record.folder)?.identifier,
            models: ClaudeCodeModelChoices.choices(with: [defaultModel, record.model]), permissionModes: offeredModes(upTo: widestMode))
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
