import Foundation
import SessionProtocol

/// The last usage reading of one account of an agent. An account keeps
/// it after its threads are gone (decision of 2026-11-13), because the
/// user picks an account by the usage that is left on it.
public struct AccountUsageReading: Codable, Equatable, Sendable {
    /// The agent as the session process names it, such as `claude-code`.
    public var agent: String
    /// The name of the account, or `nil` for the account of the login shell.
    public var account: String?
    public var windows: [ThreadUsageWindow]
    public var readAt: Date

    public init(agent: String, account: String?, windows: [ThreadUsageWindow], readAt: Date) {
        (self.agent, self.account, self.windows, self.readAt) = (agent, account, windows, readAt)
    }

    /// The newest reading of each account, in the order of their first
    /// readings.
    public static func newest(_ readings: [Self]) -> [Self] {
        var kept: [Self] = []
        for reading in readings {
            guard let index = kept.firstIndex(where: { $0.agent == reading.agent && $0.account == reading.account }) else {
                kept.append(reading)
                continue
            }
            if reading.readAt > kept[index].readAt { kept[index] = reading }
        }
        return kept
    }
}
