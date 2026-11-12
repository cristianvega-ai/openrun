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
    /// Whether the session process keeps agent threads and takes the
    /// thread requests. An older process answers them with a failure.
    public let threads: Bool
    /// The identifier of the build of the session process. The app
    /// compares it with its own build after an update. An older process
    /// sends none.
    public let build: String?

    public init(
        orderedResizeConfirmation: Bool = false, sessionChanges: Bool = false, projectsAndSettings: Bool = false, threads: Bool = false,
        build: String? = nil
    ) {
        self.build = build
        self.orderedResizeConfirmation = orderedResizeConfirmation
        self.sessionChanges = sessionChanges
        self.projectsAndSettings = projectsAndSettings
        self.threads = threads
    }

    private enum CodingKeys: String, CodingKey {
        case orderedResizeConfirmation
        case sessionChanges
        case projectsAndSettings
        case threads
        case build
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        orderedResizeConfirmation = try values.decodeIfPresent(Bool.self, forKey: .orderedResizeConfirmation) ?? false
        sessionChanges = try values.decodeIfPresent(Bool.self, forKey: .sessionChanges) ?? false
        projectsAndSettings = try values.decodeIfPresent(Bool.self, forKey: .projectsAndSettings) ?? false
        threads = try values.decodeIfPresent(Bool.self, forKey: .threads) ?? false
        build = try values.decodeIfPresent(String.self, forKey: .build)
    }
}
