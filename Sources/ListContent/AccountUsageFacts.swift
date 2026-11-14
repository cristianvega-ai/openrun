import AccountUsage
import Foundation
import SessionProtocol

/// The usage of each account for the foot of the first pane and for the
/// settings window, from the readings that the agents gave in the
/// threads (proposal 7).
public enum AccountUsageFacts {
    /// The agents in the order of the foot. An agent of a later build
    /// comes after them.
    private static let agentOrder = ["claude-code", "codex"]

    /// The newest reading of each account among the threads.
    public static func readings(of threads: [ThreadSummary]) -> [AccountUsageReading] {
        AccountUsageReading.newest(threads.compactMap { thread in
            guard let readAt = thread.usageReadAt, let windows = thread.usageWindows, windows.contains(where: { $0.usedFraction != nil }) else { return nil }
            return AccountUsageReading(agent: thread.agent, account: thread.accountName, windows: windows, readAt: readAt)
        })
    }

    /// One display for each account with a reading: the newest reading
    /// among its threads and the kept readings. The account of the login
    /// shell, which has no name, comes before the other accounts of its
    /// agent.
    public static func displays(of threads: [ThreadSummary], kept: [AccountUsageReading] = [], now: Date = Date(), timeZone: TimeZone = .current) -> [AccountUsageDisplay] {
        let rank = { (reading: AccountUsageReading) in [String(agentOrder.firstIndex(of: reading.agent) ?? agentOrder.count), reading.agent, reading.account ?? ""] }
        return AccountUsageReading.newest(kept + readings(of: threads))
            .sorted { rank($0).lexicographicallyPrecedes(rank($1)) }
            .map { display(of: $0, now: now, timeZone: timeZone) }
    }

    private static func display(of reading: AccountUsageReading, now: Date, timeZone: TimeZone) -> AccountUsageDisplay {
        var (time, day) = (Date.FormatStyle(date: .omitted, time: .shortened), Date.FormatStyle().weekday(.wide).hour().minute())
        var date = Date.FormatStyle().month(.abbreviated).day()
        (time.timeZone, day.timeZone, date.timeZone) = (timeZone, timeZone, timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // A kept reading can be days old, and its time alone would look current.
        let isToday = calendar.isDate(reading.readAt, inSameDayAs: now)
        let readTime = isToday ? reading.readAt.formatted(time) : reading.readAt.formatted(date)
        var (windows, words): ([AccountUsageDisplay.Window], [String]) = ([], [])
        for window in reading.windows {
            guard let used = window.usedFraction else { continue }
            let name = ThreadRowFacts.windowName(window)
            windows.append(.init(name: name, usedFraction: used, isAtLimit: window.status == "rejected"))
            words.append("\(name) \(Int((used * 100).rounded()))% used" + (window.resetTime.map { ", resets \($0.formatted(day))" } ?? ""))
        }
        let title = ThreadRowFacts.agentName(reading.agent) + (reading.account.map { " · \($0)" } ?? "")
        let when = isToday ? readTime : "\(readTime), \(reading.readAt.formatted(time))"
        let help = "\(title): \(words.joined(separator: ". ")). Read at \(when)."
        return AccountUsageDisplay(title: title, windows: windows, readTime: readTime, help: help, agent: reading.agent, account: reading.account)
    }
}
