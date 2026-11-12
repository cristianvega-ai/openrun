import Foundation

/// One window of the usage limit of the account of a thread, such as the
/// week, as the agent reported it (proposal 7 of 2026-11-10).
public struct ThreadUsageWindow: Codable, Equatable, Sendable {
    /// The word of the agent for the window, such as `seven_day`.
    public var name: String
    public var lengthInMinutes: Int?
    /// The used part of the window, from 0 to 1.
    public var usedFraction: Double?
    public var resetTime: Date?
    /// The word of the agent for the state, such as `allowed` or `rejected`.
    public var status: String?

    public init(name: String, lengthInMinutes: Int? = nil, usedFraction: Double? = nil, resetTime: Date? = nil, status: String? = nil) {
        (self.name, self.lengthInMinutes, self.usedFraction, self.resetTime, self.status) = (name, lengthInMinutes, usedFraction, resetTime, status)
    }
}
