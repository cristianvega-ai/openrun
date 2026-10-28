/// Additive features that the session process offers to its clients.
public struct ServerCapabilities: Codable, Equatable, Sendable {
    public let orderedResizeConfirmation: Bool

    public init(orderedResizeConfirmation: Bool = false) {
        self.orderedResizeConfirmation = orderedResizeConfirmation
    }

    private enum CodingKeys: String, CodingKey {
        case orderedResizeConfirmation
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        orderedResizeConfirmation = try values.decodeIfPresent(Bool.self, forKey: .orderedResizeConfirmation) ?? false
    }
}
