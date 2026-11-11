/// What a read of one file of the data folder found.
public enum DataReadResult<Document: DataDocument>: Sendable {
    /// The file does not exist yet.
    case missing
    case document(Document)
    /// The file could not be read as a document of this build. It now has
    /// the name at `path`, and the caller starts from the defaults.
    case setAside(path: String)

    /// The document, or `nil` when the caller starts from the defaults.
    public var document: Document? {
        if case .document(let document) = self { document } else { nil }
    }
}
