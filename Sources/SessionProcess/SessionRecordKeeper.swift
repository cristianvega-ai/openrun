import Dispatch
import Foundation
import SessionProtocol
import SessionRecords

/// Keeps `sessions.json` in step with the sessions that run, so that they
/// come back after a restart of the session process, such as after a
/// restart of the Mac (decision of 2026-10-15).
///
/// The keeper runs on a serial queue of its own, as the other keepers do,
/// because a save waits for the disk.
actor SessionRecordKeeper {
    private let queue = DispatchSerialQueue(label: "ai.cristianvega.openrun.session-records")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    /// A change waits this long for the changes that follow it, such as
    /// the sizes of a window that the user drags.
    static let saveDelay = Duration.milliseconds(300)

    private let store: SessionRecordStore
    private let saveDelay: Duration
    private var records: [UUID: SessionRecord] = [:]
    private var pendingSave: Task<Void, Never>?

    init(store: SessionRecordStore, saveDelay: Duration = SessionRecordKeeper.saveDelay) {
        (self.store, self.saveDelay) = (store, saveDelay)
    }

    /// The sessions that ran when the session process stopped, oldest
    /// first. A file that cannot be read never stops the start.
    nonisolated func load() -> [SessionRecord] {
        do {
            let loaded = try store.load()
            if let path = loaded.setAsidePath { SessionLog.write("The file of the sessions could not be read and now has the name ", detail: path) }
            return loaded.records
        } catch {
            SessionLog.write("The sessions of the last run could not be read: ", detail: "\(error)")
            return []
        }
    }

    /// Takes the new facts of a session that runs.
    func keep(_ summary: SessionSummary) {
        let record = SessionRecord(
            identifier: summary.identifier, folder: summary.currentFolder ?? summary.folder, name: summary.name,
            columns: Int(summary.size.columns), rows: Int(summary.size.rows), createdAt: summary.createdAt)
        guard records[summary.identifier] != record else { return }
        records[summary.identifier] = record
        saveSoon()
    }

    private func saveSoon() {
        guard pendingSave == nil else { return }
        pendingSave = Task {
            try? await Task.sleep(for: saveDelay)
            if !Task.isCancelled { self.save() }
        }
    }

    private func save() {
        pendingSave = nil
        do {
            try store.save(records.values.sorted { $0.createdAt < $1.createdAt })
        } catch {
            SessionLog.write("The sessions could not be saved, so they do not come back after a restart: ", detail: "\(error)")
        }
    }
}
