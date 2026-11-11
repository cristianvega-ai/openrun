import DataStorage

/// A document for the tests, stored in the file of the layout, which no
/// other module of this package writes yet.
struct SampleDocument: DataDocument, Equatable {
    static let file = DataFile.layout
    static let format = 2
    static let knownKeys: Set<String> = ["name", "folder", "count", "note"]

    var name: String
    var folder: String
    var count: Int
    /// Left out of the file when `nil`, as a setting at its default is.
    var note: String? = nil
}
