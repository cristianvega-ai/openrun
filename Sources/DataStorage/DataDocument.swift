/// The content of one file of the data folder.
///
/// Each file holds a format number beside the content, so a later build
/// can still read a file of an older build. `DataFolder` writes the number
/// and checks it, and the document type does not hold it.
public protocol DataDocument: Codable, Sendable {
    /// The file that holds this document.
    static var file: DataFile { get }
    /// The format that this build writes. A file with a higher number comes
    /// from a later build, and this build cannot read it. Raise the number
    /// when the meaning of a field changes, and keep the decode of each
    /// older format.
    static var format: Int { get }
}
