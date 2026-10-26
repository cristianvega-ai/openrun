/// The kinds of underline that SGR 4 can ask for. The raw values are the
/// numbers of libghostty-vt, so a style converts without a table.
public enum UnderlineStyle: Int32, Equatable, Hashable, Sendable {
    case none = 0, single, double, curly, dotted, dashed
}
