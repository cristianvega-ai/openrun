/// The agent ended its work on a user message.
public struct TurnEnd: Codable, Sendable, Hashable {
    public enum Outcome: String, Codable, Sendable {
        /// The agent finished its answer.
        case done
        /// The user stopped the turn.
        case stopped
        /// An error ended the turn.
        case failed
    }

    public var outcome: Outcome
    /// What went wrong, for a failed turn.
    public var errorText: String?
    /// The kind of the error, when the agent names one: `notSignedIn`, or
    /// the agent's own word for another kind.
    public var errorKind: String?
    /// The agent has no valid login, so each turn fails until the user
    /// signs in.
    public static let notSignedIn = "notSignedIn"
    public var usage: TokenUsage?
    /// The time of the whole turn.
    public var durationMilliseconds: Int?
    /// The part of that time that the model's service took.
    public var serviceDurationMilliseconds: Int?
    /// The agent's estimate of the cost at list price. A subscription does
    /// not bill it, so it is only an estimate.
    public var estimatedCostInDollars: Double?

    public init(
        outcome: Outcome, errorText: String? = nil, errorKind: String? = nil, usage: TokenUsage? = nil, durationMilliseconds: Int? = nil,
        serviceDurationMilliseconds: Int? = nil, estimatedCostInDollars: Double? = nil
    ) {
        self.outcome = outcome
        (self.errorText, self.errorKind) = (errorText, errorKind)
        self.usage = usage
        self.durationMilliseconds = durationMilliseconds
        self.serviceDurationMilliseconds = serviceDurationMilliseconds
        self.estimatedCostInDollars = estimatedCostInDollars
    }
}
