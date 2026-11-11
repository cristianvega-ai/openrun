import Foundation

/// What the first pane shows of one project.
public struct ProjectDisplay: Equatable, Sendable {
    public var identifier: UUID
    public var name: String
    /// The folder of the project, for the help tag of its row.
    public var folder: String
    /// The rows of the sessions list in this project that need the user.
    public var attentionCount: Int

    public init(identifier: UUID, name: String, folder: String, attentionCount: Int = 0) {
        (self.identifier, self.name, self.folder, self.attentionCount) = (identifier, name, folder, attentionCount)
    }
}
