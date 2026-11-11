/// Additive features that the session process offers to its clients.
public struct ServerCapabilities: Codable, Equatable, Sendable {
    public let orderedResizeConfirmation: Bool
    /// The session process sends the facts of each session and takes
    /// `receiveSessionChanges`, `renameSession`, `raiseSessionAlert` and
    /// `clearSessionAlert`.
    public let sessionChanges: Bool

    public init(orderedResizeConfirmation: Bool = false, sessionChanges: Bool = false) {
        self.orderedResizeConfirmation = orderedResizeConfirmation
        self.sessionChanges = sessionChanges
    }

    private enum CodingKeys: String, CodingKey {
        case orderedResizeConfirmation
        case sessionChanges
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        orderedResizeConfirmation = try values.decodeIfPresent(Bool.self, forKey: .orderedResizeConfirmation) ?? false
        sessionChanges = try values.decodeIfPresent(Bool.self, forKey: .sessionChanges) ?? false
    }
}
