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
    /// The keys at the top of the file that this build reads and writes,
    /// apart from `format`. A write keeps every other key of the file as it
    /// is, so a key of a later build is not lost. A known key that the
    /// document leaves out, such as a setting at its default, goes away.
    static var knownKeys: Set<String> { get }
}
