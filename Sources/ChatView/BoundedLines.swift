/// The first lines of a long text, such as the output of a tool, and the
/// count of the lines that it leaves out.
///
/// The view shows only the start, so ten thousand lines of output cost no
/// more than a few. It reads the rest only to count its lines.
struct BoundedLines: Equatable {
    var text: Substring
    var hiddenLineCount: Int

    init(_ whole: String, lineLimit: Int) {
        let utf8 = whole.utf8
        var end = utf8.firstIndex(of: 10) ?? utf8.endIndex
        var lines = 1
        // A line end that is the last byte starts no new line.
        while lines < lineLimit, end < utf8.endIndex, utf8.index(after: end) < utf8.endIndex {
            end = utf8[utf8.index(after: end)...].firstIndex(of: 10) ?? utf8.endIndex
            lines += 1
        }
        text = whole[..<end]
        let rest = utf8[end...].dropFirst()
        hiddenLineCount = rest.isEmpty ? 0 : rest.reduce(1) { $0 + ($1 == 10 ? 1 : 0) } - (rest.last == 10 ? 1 : 0)
    }
}
