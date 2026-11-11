import SessionProtocol

/// Finds the thread that a typed identifier means: any unique start of the
/// identifier, as for a session.
enum ThreadMatch {
    static func find(_ typed: String, in threads: [ThreadSummary]) throws -> ThreadSummary {
        let wanted = typed.lowercased()
        let matches = threads.filter { $0.identifierText.hasPrefix(wanted) }
        if let exact = matches.first(where: { $0.identifierText == wanted }) { return exact }
        switch matches.count {
        case 0:
            throw CommandLineToolError.failure("No thread has an identifier that starts with \(typed). Run 'openrun thread list' to see the threads.")
        case 1:
            return matches[0]
        default:
            throw CommandLineToolError.failureWithList(
                heading: "More than one thread starts with \(typed). Type more characters.",
                lines: matches.map { "  \($0.identifierText)  \($0.name ?? $0.title ?? "")" })
        }
    }
}
