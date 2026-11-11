import AgentConversation
import Foundation

/// The usage reading in a `rate_limit_event` of Claude Code.
///
/// The documentation of the event does not list `unifiedWindows`, which
/// the live event has, so the reading keeps each field that it does not
/// read, for a later version to use.
enum ClaudeCodeUsage {
    static func reading(from information: JSONValue) -> UsageReading {
        var windows: [UsageWindow] = []
        if let named = information["unifiedWindows"]?.object {
            for name in named.keys.sorted() {
                let window = named[name] ?? .null
                windows.append(UsageWindow(
                    name: name, lengthInMinutes: lengthInMinutes(ofWindowNamed: name),
                    usedFraction: window["utilization"]?.number, resetTime: time(window["resetsAt"]),
                    status: window["status"]?.string))
            }
        } else if let name = information["rateLimitType"]?.string {
            // An older form names one window at the top of the event.
            windows.append(UsageWindow(
                name: name, lengthInMinutes: lengthInMinutes(ofWindowNamed: name),
                usedFraction: information["utilization"]?.number, resetTime: time(information["resetsAt"]),
                status: information["status"]?.string))
        }
        var otherFields = information.object ?? [:]
        otherFields["unifiedWindows"] = nil
        otherFields["status"] = nil
        return UsageReading(windows: windows, status: information["status"]?.string, otherFields: otherFields)
    }

    /// The length of a window from its name, such as 300 for `five_hour`
    /// and 10080 for `seven_day_opus`, or nil for a name of another form.
    static func lengthInMinutes(ofWindowNamed name: String) -> Int? {
        let words = name.lowercased().split(separator: "_")
        guard words.count >= 2, let count = Int(words[0]) ?? numberWords[String(words[0])] else { return nil }
        let unit = words[1].hasSuffix("s") ? words[1].dropLast() : words[1]
        let minutes: [Substring: Int] = ["minute": 1, "hour": 60, "day": 1_440, "week": 10_080]
        return minutes[unit].map { $0 * count }
    }

    private static let numberWords = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirty": 30,
    ]

    /// A time in Unix seconds, as the event gives it.
    private static func time(_ value: JSONValue?) -> Date? {
        value?.number.map { Date(timeIntervalSince1970: $0) }
    }
}
