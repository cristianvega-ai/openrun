import AccountUsage
import Foundation
import ProjectsList
import SessionProtocol

/// The usage of each account for the foot of the first pane, from the
/// readings that the agents gave in the threads (proposal 7).
public enum AccountUsageFacts {
    /// The agents in the order of the foot. An agent of a later build
    /// comes after them.
    private static let agentOrder = ["claude-code", "codex"]

    /// One display for each account with a reading: the newest reading
    /// among its threads. The account of the login shell, which has no
    /// name, comes before the other accounts of its agent.
    public static func displays(of threads: [ThreadSummary], timeZone: TimeZone = .current) -> [AccountUsageDisplay] {
        var newest: [[String]: ThreadSummary] = [:]
        for thread in threads {
            guard let readAt = thread.usageReadAt, thread.usageWindows?.contains(where: { $0.usedFraction != nil }) == true else { continue }
            let rank = String(agentOrder.firstIndex(of: thread.agent) ?? agentOrder.count)
            let key = [rank, thread.agent, thread.accountName ?? ""]
            if let kept = newest[key]?.usageReadAt, kept >= readAt { continue }
            newest[key] = thread
        }
        return newest.sorted { $0.key.lexicographicallyPrecedes($1.key) }.compactMap { display(of: $0.value, timeZone: timeZone) }
    }

    private static func display(of thread: ThreadSummary, timeZone: TimeZone) -> AccountUsageDisplay? {
        guard let readAt = thread.usageReadAt else { return nil }
        var (time, day) = (Date.FormatStyle(date: .omitted, time: .shortened), Date.FormatStyle().weekday(.wide).hour().minute())
        (time.timeZone, day.timeZone) = (timeZone, timeZone)
        var (windows, words): ([AccountUsageDisplay.Window], [String]) = ([], [])
        for window in thread.usageWindows ?? [] {
            guard let used = window.usedFraction else { continue }
            let name = ThreadRowFacts.windowName(window)
            windows.append(.init(name: name, usedFraction: used, isAtLimit: window.status == "rejected"))
            words.append("\(name) \(Int((used * 100).rounded()))% used" + (window.resetTime.map { ", resets \($0.formatted(day))" } ?? ""))
        }
        let title = ThreadRowFacts.agentName(thread.agent) + (thread.accountName.map { " · \($0)" } ?? "")
        let help = "\(title): \(words.joined(separator: ". ")). Read at \(readAt.formatted(time))."
        return AccountUsageDisplay(title: title, windows: windows, readTime: readAt.formatted(time), help: help)
    }
}
