import Dispatch
import Foundation
import Projects

/// The one owner of the projects (decision of 2026-11-10). It loads them
/// when the session process starts, and saves each change at once, before
/// the client hears of it.
///
/// The keeper runs on a serial queue of its own. A save waits for the disk
/// (`F_FULLFSYNC`), and the threads of Swift concurrency serve the output
/// and the input of the sessions, so no save takes one of them.
actor ProjectKeeper {
    private let queue = DispatchSerialQueue(label: "ai.cristianvega.openrun.projects")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private let store: ProjectStore
    private(set) var list: ProjectList
    /// Rises with each change, so a reader that gets two lists out of order
    /// keeps the newer one (see `SessionRegistry.updateProjects`).
    private(set) var version = 0

    /// Loads the projects. A file that cannot be read never stops the
    /// start: the list starts without it, and the log says so.
    init(store: ProjectStore) {
        self.store = store
        list = Self.load(from: store)
    }

    private static func load(from store: ProjectStore) -> ProjectList {
        do {
            let loaded = try store.load()
            for path in loaded.setAsidePaths {
                SessionLog.write("A file of the projects could not be read and now has the name ", detail: path)
            }
            let hidden = loaded.list.projectsWithoutFolder.count
            if hidden > 0 { SessionLog.write("\(hidden) projects have no folder on this Mac, so they hold no session.") }
            return loaded.list
        } catch {
            // A save reads the files first and throws too, so no change can
            // replace the projects that this load did not read.
            SessionLog.write("The projects could not be read, and each change of them fails until they can: ", detail: "\(error)")
            return ProjectList()
        }
    }

    /// Adds a folder at the end of the list. See `ProjectList.add`.
    func add(folder: String, name: String?, currentFolder: String?) throws -> (project: Project, list: ProjectList, version: Int) {
        let project = try change { try $0.add(folder: folder, name: name, currentFolder: currentFolder) }
        return (project, list, version)
    }

    func remove(identifier: UUID) throws -> (list: ProjectList, version: Int) {
        try change { try $0.remove(identifier: identifier) }
        return (list, version)
    }

    func rename(identifier: UUID, to name: String?) throws -> (list: ProjectList, version: Int) {
        try change { try $0.rename(identifier: identifier, to: name) }
        return (list, version)
    }

    func move(identifier: UUID, to place: Int) throws -> (list: ProjectList, version: Int) {
        try change { try $0.move(identifier: identifier, to: place) }
        return (list, version)
    }

    /// Makes the change on a copy, saves the copy, and only then keeps it.
    ///
    /// - Throws: `ProjectListError` for a change that the list refuses, or
    ///   `DataSaveFailure`. In both cases the list stays as it was. A save
    ///   writes two files, and the first can hold the change when the
    ///   second fails, so the old list is written once more.
    @discardableResult
    private func change<Result>(_ edit: (inout ProjectList) throws -> Result) throws -> Result {
        var changed = list
        let result = try edit(&changed)
        do {
            try store.save(changed)
        } catch {
            try? store.save(list)
            SessionLog.write("A change of the projects could not be saved: ", detail: "\(error)")
            throw DataSaveFailure(subject: "the projects", reason: "\(error)")
        }
        list = changed
        version += 1
        return result
    }
}
