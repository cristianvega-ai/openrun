import AccountUsage
import ListContent

/// The last usage reading of each account. It stays after the threads of
/// the account are gone (decision of 2026-11-13), because OpenRun sends
/// no request only to get a new reading.
extension Workspace {
    /// Takes the newer readings of the threads, and writes them to the
    /// data folder when one changed.
    func keepUsage() {
        let newest = AccountUsageReading.newest(keptUsage + AccountUsageFacts.readings(of: connection.overview.threads))
        guard newest != keptUsage else { return }
        keptUsage = newest
        usageStore.save(newest)
    }

    /// The kept readings of the accounts that the settings still hold. A
    /// thread of an account that the settings lost still shows its own
    /// reading.
    var shownKeptUsage: [AccountUsageReading] {
        keptUsage.filter { reading in
            guard let account = reading.account else { return true }
            let accounts = reading.agent == "codex" ? settings.codexAccounts : reading.agent == "claude-code" ? settings.claudeCodeAccounts : []
            return accounts.contains { $0.name == account }
        }
    }
}
