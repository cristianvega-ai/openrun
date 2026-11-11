import AgentConversation
import Foundation

/// The usage reading in the rate limits of a Codex account.
///
/// The reading has a `primary` and a `secondary` window. Every account of
/// the prototype had only a weekly primary window, so each window takes a
/// name from its length, such as `seven_day`, and not from its place.
enum CodexUsage {
    static func reading(from limits: JSONValue) -> UsageReading {
        let windows = ["primary", "secondary"].compactMap { place -> UsageWindow? in
            guard let window = limits[place], window.object != nil else { return nil }
            let minutes = window["windowDurationMins"]?.integer
            return UsageWindow(
                name: minutes.map(name(ofWindowWithLength:)) ?? place, lengthInMinutes: minutes,
                usedFraction: window["usedPercent"]?.number.map { $0 / 100 },
                resetTime: window["resetsAt"]?.number.map { Date(timeIntervalSince1970: $0) })
        }
        var otherFields = limits.object ?? [:]
        otherFields["primary"] = nil
        otherFields["secondary"] = nil
        // Codex gives no state for each window. The kind of limit that the
        // account reached, such as `rate_limit_reached`, is its state.
        otherFields["rateLimitReachedType"] = nil
        return UsageReading(windows: windows, status: limits["rateLimitReachedType"]?.string, otherFields: otherFields)
    }

    /// A name from the length of a window, such as `5_hour` for 300 and
    /// `seven_day` for 10080. The week has the name that Claude Code gives
    /// its own weekly window.
    static func name(ofWindowWithLength minutes: Int) -> String {
        switch minutes {
        case 10_080: "seven_day"
        case let length where length % 1_440 == 0: "\(length / 1_440)_day"
        case let length where length % 60 == 0: "\(length / 60)_hour"
        default: "\(minutes)_minute"
        }
    }
}
