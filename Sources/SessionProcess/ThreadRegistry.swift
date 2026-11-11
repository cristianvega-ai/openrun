import AgentThreads
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
    /// The model and the permission mode of a thread that names none.
    var defaultModel = "opus"
    var defaultPermissionMode = "default"

    /// Loads the threads. A file that cannot be read never stops the
    /// start: the list starts empty, and the log says so.
    init(
        store: ThreadStore, projects: ProjectList = ProjectList(), changes: SessionChangeFeed? = nil,
        launchSettings: @escaping @Sendable () async throws -> AgentLaunchSettings
    ) {
        (self.store, self.projects, self.changes, self.launchSettings) = (store, projects, changes, launchSettings)
        var loaded = ThreadList()
        do {
            let result = try store.load()
            if let path = result.setAsidePath { SessionLog.write("The file of the threads could not be read and now has the name ", detail: path) }
            loaded = result.list
        } catch {
            SessionLog.write("The threads could not be read, and each change of them fails until they can: ", detail: "\(error)")
        }
        let first = loaded.threads.map { Self.summary(of: $0, in: projects) }
        list = loaded
        summaries = Dictionary(first.map { ($0.identifier, $0) }, uniquingKeysWith: { summary, _ in summary })
        changes?.replaceThreads(first)
    }

    /// Every thread, oldest first.
    var allSummaries: [ThreadSummary] {
        list.threads.compactMap { summaries[$0.identifier] }
    }

    func summary(_ identifier: UUID) -> ThreadSummary? {
        summaries[identifier]
    }

    /// Whether a process of an agent runs, so the session process must stay.
    var hasRunningProcess: Bool {
        summaries.values.contains { $0.isProcessRunning }
    }

    /// The summary of a thread that is not in use: idle, with no process.
    static func summary(of record: ThreadRecord, in projects: ProjectList) -> ThreadSummary {
        ThreadSummary(
            identifier: record.identifier, agent: record.agent.rawValue, folder: record.folder, model: record.model,
            permissionMode: record.permissionMode, name: record.name, title: record.title, accountName: record.account?.name,
            createdAt: record.createdAt, lastActivityAt: record.lastActivityAt,
            projectIdentifier: projects.project(holding: record.folder)?.identifier)
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
