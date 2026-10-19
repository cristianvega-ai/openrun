import SessionProtocol

/// `openrun read`: the screen of a session as plain text.
struct ReadCommand {
    var identifier: String
    var includeScrollback: Bool

    func run(location: SocketLocation) throws -> String {
        let client = try SessionClient(location: location)
        let session = try client.session(matching: identifier)
        guard case .screen(let text) = try client.request(.readScreen(identifier: session.identifier, includeScrollback: includeScrollback)) else {
            throw CommandLineToolError.failure("The session process gave an unexpected answer to the read request.")
        }
        return text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
    }
}
