import AgentThreads
import Foundation
import Projects
import SessionProtocol

/// The changes of the threads: a new thread, a name, a close, and the
/// facts that a runner reports.
extension ThreadRegistry {
    /// Makes a thread. Its folder must exist, because the agent starts there.
    func create(agent: String, folder: String, model: String?, permissionMode: String?, name: String?) throws -> ThreadSummary {
        guard ThreadAgent(rawValue: agent) == .claudeCode else {
            throw ThreadRequestError.unsupportedAgent(agent)
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
        let record = ThreadRecord(
            agent: .claudeCode, folder: realFolder, model: model ?? defaultModel, permissionMode: permissionMode ?? defaultPermissionMode, name: name)
        let previous = list
        try list.add(record)
        try save(restoring: previous)
        let summary = Self.summary(of: list.thread(record.identifier) ?? record, in: projects)
        summaries[record.identifier] = summary
        changes?.threadChanged(summary)
        return summary
    }

    func rename(_ identifier: UUID, to name: String?) async throws {
        let previous = list
        try list.update(identifier) { $0.name = name }
        try save(restoring: previous)
        await runners[identifier]?.setName(list.thread(identifier)?.name)
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
    }

    /// The runner of a thread, which starts with the first use.
    func runner(for identifier: UUID) throws -> ThreadRunner {
        if let runner = runners[identifier] { return runner }
        guard let record = list.thread(identifier) else { throw ThreadListError.unknownThread(identifier) }
        let runner = ThreadRunner(record: record, launchSettings: launchSettings) { [weak self] in await self?.runnerChanged($0) }
        runners[identifier] = runner
        return runner
    }

    /// A runner has a new title, state or process. The record goes to the
    /// file when it changed, and the summary goes to the clients.
    func runnerChanged(_ runner: ThreadRunner) async {
        let (record, state, process, waiting) = await (runner.record, runner.state, runner.program?.processIdentifier, runner.waitingMessages.count)
        guard runners[record.identifier] === runner, let kept = list.thread(record.identifier) else { return }
        agentProcesses = agentProcesses.filter { $0.value != record.identifier }
        if let process { agentProcesses[process] = record.identifier }
        let isRunning = process != nil
        if kept != record {
            try? list.update(record.identifier) { $0 = record }
            do { try store.save(list) } catch { SessionLog.write("The facts of a thread could not be saved: ", detail: "\(error)") }
        }
        var summary = Self.summary(of: list.thread(record.identifier) ?? record, in: projects)
        (summary.state, summary.isProcessRunning, summary.waitingMessageCount) = (state.rawValue, isRunning, waiting)
        guard summaries[record.identifier] != summary else { return }
        summaries[record.identifier] = summary
        changes?.threadChanged(summary)
    }

    /// Sends the summary of a thread again after a change of its record.
    private func publish(_ identifier: UUID) {
        guard let record = list.thread(identifier), var summary = summaries[identifier] else { return }
        let fresh = Self.summary(of: record, in: projects)
        (summary.name, summary.title, summary.projectIdentifier) = (fresh.name, fresh.title, fresh.projectIdentifier)
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
        runners = [:]
    }
}
