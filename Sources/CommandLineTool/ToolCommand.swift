/// A command the user typed, after the arguments are checked.
enum ToolCommand: Equatable {
    case new(folder: String?, program: [String])
    case list(printsJSON: Bool)
    case attach(identifier: String)
    case read(identifier: String, includeScrollback: Bool)
    case send(identifier: String, text: String, pressEnter: Bool)
    case kill(identifier: String)
    /// A nil name removes the name.
    case rename(identifier: String, name: String?)
    /// A nil identifier means the session of the caller.
    case notify(identifier: String?, text: String)
    case projectList(printsJSON: Bool)
    case help
}
