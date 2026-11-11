/// A document and its format number, as one JSON object in the file.
///
/// The number and the fields of the document share one object, so the file
/// stays flat and easy to read: `"format"` sits beside the other keys.
struct FormattedDocument<Document: DataDocument>: Encodable {
    let document: Document

    func encode(to encoder: any Encoder) throws {
        try document.encode(to: encoder)
        var container = encoder.container(keyedBy: FormatKey.self)
        try container.encode(Document.format, forKey: .format)
    }
}

/// The one key that every file of the data folder holds.
struct FormatKey: CodingKey {
    static let format = FormatKey(stringValue: "format")

    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
