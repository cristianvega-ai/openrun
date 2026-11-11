import Foundation

/// One window of an account's usage limit, such as the week.
public struct UsageWindow: Codable, Sendable, Hashable {
    /// The agent's name for the window, such as `seven_day`.
    public var name: String
    /// The length of the window, when the name or the agent tells it.
    /// Both agents showed only a weekly window, so a view labels each
    /// window by its length and not by its place.
    public var lengthInMinutes: Int?
    /// The used part of the window, from 0 to 1.
    public var usedFraction: Double?
    public var resetTime: Date?
    /// The agent's word for the state at the limit, such as `allowed`,
    /// `allowed_warning` or `rejected`.
    public var status: String?

    public init(name: String, lengthInMinutes: Int? = nil, usedFraction: Double? = nil, resetTime: Date? = nil, status: String? = nil) {
        self.name = name
        self.lengthInMinutes = lengthInMinutes
        self.usedFraction = usedFraction
        self.resetTime = resetTime
        self.status = status
    }
}
