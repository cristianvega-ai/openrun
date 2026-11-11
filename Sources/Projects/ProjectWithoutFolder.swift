import Foundation

/// A project of `projects.json` whose folder this Mac does not know, for
/// example after `project-folders.json` was set aside, or later a project
/// that a sync brings from another Mac. The sessions list does not show
/// it, but a client can list it and offer to remove it.
public struct ProjectWithoutFolder: Hashable, Sendable {
    public let identifier: UUID
    /// The name that the user gave, or `nil`.
    public let name: String?
}
