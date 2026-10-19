/// A command the user typed, after the arguments are checked.
enum ToolCommand: Equatable {
    case new(folder: String?, program: [String])
    case list
    case read(identifier: String, includeScrollback: Bool)
    case send(identifier: String, text: String, pressEnter: Bool)
    case kill(identifier: String)
    case help
}
