/// Additive features that the session process offers to its clients.
public struct ServerCapabilities: Codable, Equatable, Sendable {
    public let orderedResizeConfirmation: Bool
    /// The session process sends the facts of each session and takes
    /// `receiveSessionChanges`, `renameSession`, `raiseSessionAlert` and
    /// `clearSessionAlert`.
    public let sessionChanges: Bool
    /// The session process keeps the projects and the settings. It takes
    /// their requests, sends the project of each session, and sends both
    /// lists after the session list to a connection that asked with
    /// `receiveSessionChanges`.
    public let projectsAndSettings: Bool

    public init(orderedResizeConfirmation: Bool = false, sessionChanges: Bool = false, projectsAndSettings: Bool = false) {
        self.orderedResizeConfirmation = orderedResizeConfirmation
        self.sessionChanges = sessionChanges
        self.projectsAndSettings = projectsAndSettings
    }

    private enum CodingKeys: String, CodingKey {
        case orderedResizeConfirmation
        case sessionChanges
        case projectsAndSettings
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        orderedResizeConfirmation = try values.decodeIfPresent(Bool.self, forKey: .orderedResizeConfirmation) ?? false
        sessionChanges = try values.decodeIfPresent(Bool.self, forKey: .sessionChanges) ?? false
        projectsAndSettings = try values.decodeIfPresent(Bool.self, forKey: .projectsAndSettings) ?? false
    }
}
