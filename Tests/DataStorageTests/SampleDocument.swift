import DataStorage

/// A document for the tests, stored in the file of the layout, which no
/// other module of this package writes yet.
struct SampleDocument: DataDocument, Equatable {
    static let file = DataFile.layout
    static let format = 2

    var name: String
    var folder: String
    var count: Int
}
