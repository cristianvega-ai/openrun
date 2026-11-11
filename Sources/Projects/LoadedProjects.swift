/// What `ProjectStore.load` found.
public struct LoadedProjects: Sendable {
    public let list: ProjectList
    /// The new paths of files that could not be read and were set aside.
    /// The caller can tell the user, and must not log the paths in public.
    public let setAsidePaths: [String]
}
