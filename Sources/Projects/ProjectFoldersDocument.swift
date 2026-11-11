import DataStorage

/// The folder of each project on this Mac, by the identifier of the
/// project. Another Mac can hold the same project in another folder.
struct ProjectFoldersDocument: DataDocument {
    static let file = DataFile.projectFolders
    static let format = 1
    static let knownKeys: Set<String> = ["folders"]

    /// The keys are the identifiers in the form of `UUID.uuidString`.
    var folders: [String: String]
}
