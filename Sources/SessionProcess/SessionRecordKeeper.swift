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
    /// How long the record of a session stays after its program ended.
    /// At a shutdown of the Mac, the programs can end a moment before the
    /// session process hears of the shutdown, and such a session must
    /// come back.
    static let endGrace = Duration.seconds(3)

    private let store: SessionRecordStore
    private let (saveDelay, endGrace): (Duration, Duration)
    private var records: [UUID: SessionRecord] = [:]
    /// The sessions that do not come back, such as the terminal of a thread.
    private var excluded: Set<UUID> = []
    private var isStopped = false
    private var pendingSave: Task<Void, Never>?

    init(store: SessionRecordStore, saveDelay: Duration = SessionRecordKeeper.saveDelay, endGrace: Duration = SessionRecordKeeper.endGrace) {
        (self.store, self.saveDelay, self.endGrace) = (store, saveDelay, endGrace)
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
        guard !isStopped, !excluded.contains(summary.identifier) else { return }
        let record = SessionRecord(
            identifier: summary.identifier, folder: summary.currentFolder ?? summary.folder, name: summary.name,
            columns: Int(summary.size.columns), rows: Int(summary.size.rows), createdAt: summary.createdAt)
        guard records[summary.identifier] != record else { return }
        records[summary.identifier] = record
        saveSoon()
    }

    /// The program of the session ended. When the session process still
    /// runs after the grace time, the session does not come back.
    func forget(_ identifier: UUID) {
        excluded.remove(identifier)
        guard !isStopped, records[identifier] != nil else { return }
        Task {
            try? await Task.sleep(for: endGrace)
            if !isStopped, records.removeValue(forKey: identifier) != nil { saveSoon() }
        }
    }

    /// The session never comes back, such as the terminal of a thread,
    /// whose conversation the thread keeps.
    func exclude(_ identifier: UUID) {
        excluded.insert(identifier)
        if records.removeValue(forKey: identifier) != nil { saveSoon() }
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

    /// The session process stops. The sessions that run now stay in the
    /// file, and the ends that follow change nothing.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        if let pendingSave {
            pendingSave.cancel()
            save()
        }
    }
}
