import Dispatch
import SessionProtocol
import Settings

/// The one owner of the settings (decision of 2026-11-10). It loads them
/// when the session process starts, and saves each change at once, before
/// the client hears of it.
///
/// The keeper runs on a serial queue of its own, as `ProjectKeeper` does,
/// so a save that waits for the disk takes no thread of Swift concurrency.
actor SettingKeeper {
    private let queue = DispatchSerialQueue(label: "ai.cristianvega.openrun.settings")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private let store: SettingsStore
    private let changes: SessionChangeFeed?
    private(set) var values: SettingValues
    /// Rises with each change, so a reader that gets two sets of values
    /// out of order keeps the newer one (see `SessionRegistry.updateLimits`).
    private(set) var version = 0

    /// Loads the settings. A file that cannot be read and a value that
    /// falls back to its default never stop the start, and the log says so.
    ///
    /// - Parameter changes: Gets the list now and after each change, in
    ///   the step of the change, so the watchers get the changes in order.
    init(store: SettingsStore, changes: SessionChangeFeed? = nil) {
        self.init(store: store, values: Self.load(from: store), changes: changes)
    }

    /// Starts from values that `load(from:)` gave, so the caller can hand
    /// the limits to the registry before any change.
    init(store: SettingsStore, values: SettingValues, changes: SessionChangeFeed?) {
        self.store = store
        self.changes = changes
        self.values = values
        changes?.replaceSettings(Self.summaries(of: values))
    }

    static func load(from store: SettingsStore) -> SettingValues {
        do {
            let loaded = try store.load()
            if let path = loaded.setAsidePath {
                SessionLog.write("The file of the settings could not be read and now has the name ", detail: path)
            }
            for name in loaded.fallbackNames {
                SessionLog.write("The setting \(name.rawValue) held a value that is not valid, so it is at its default.")
            }
            return loaded.values
        } catch {
            // A save reads the file first and throws too, so no change can
            // replace the settings that this load did not read.
            SessionLog.write("The settings could not be read, so each is at its default, and each change fails until they can: ", detail: "\(error)")
            return SettingValues()
        }
    }

    /// Changes one setting to the value that `text` gives, and saves it.
    ///
    /// - Throws: `SettingError` for an unknown name, a protected setting
    ///   that a client other than the app asks for, or a value that is not
    ///   valid. `DataSaveFailure` when the save fails. In each case the
    ///   values stay as they were. The file is replaced in one step, so it
    ///   still holds them too.
    func change(name: String, to text: String, requestedBy requester: SettingRequester) throws -> (values: SettingValues, version: Int) {
        var changed = values
        try changed.change(try SettingName.named(name), to: text, requestedBy: requester)
        guard changed != values else { return (values, version) }
        do {
            try store.save(changed)
        } catch {
            SessionLog.write("A change of the settings could not be saved: ", detail: "\(error)")
            throw DataSaveFailure(subject: "the settings", reason: "\(error)")
        }
        values = changed
        version += 1
        changes?.replaceSettings(Self.summaries(of: values))
        return (values, version)
    }

    /// Every setting as the protocol sends it, in the order of `SettingName`.
    static func summaries(of values: SettingValues) -> [SettingSummary] {
        SettingName.allCases.map { SettingSummary(name: $0.rawValue, text: values.text(of: $0), isProtected: $0.isProtected) }
    }
}
