/// The format number of a file, read before the rest of the file.
struct FormatHeader: Decodable {
    let format: Int
}
